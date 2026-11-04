#!/bin/sh
# حلقة فحص التوفّر ليقين — تتنادى من كل ملفات uptime*.yml.
#
# ليه ملف واحد مشترك: التغطية بقت من **تعدّد خيوط الإشعال** (uptime, uptime-b,
# uptime-c) مش من خيط واحد طويل. لو منطق الفحص اتكرّر في ٣ ملفات، أي تعديل
# مستقبلي هيتعمل في واحد وينسى التانيين — فيتغيّر معنى الفحص من غير ما حد ياخد
# باله. المنطق هنا مرّة واحدة.
set -u

# ٣ محاولات بينها ٤٥ ثانية: تعافي nginx من قتل مفاجئ ثوانٍ، وفاصل الـ١٥ ثانية
# القديم كان أقصر من عمر بلبلة DNS/شبكة على رَنَر جيت هَب فكان بيولّد إنذار كاذب.
#
# ⚠️ إصلاح 2026-11-04 (عطل 04d86416): الحد الأدنى للحجم لوحده بيربط الفحص
# بـ**شكل** الصفحة مش بحياتها. يوم 11-04 أحمد حوّل app.getyaqeen.com من نسخة
# الويب الكاملة لصفحة هبوط (٥١٠٦ بايت) ⇒ شرط «≥٢٠٠٠٠ بايت» بقى غلط، فكل
# تشغيلات uptime* فشلت وهي بتفحص موقعاً شغّالاً ١٠٠٪ (200/5106) ⇒ شبكة الأمان
# الخارجية بقت حمراء دايماً وإيميلات سقوط كاذبة. الحل: الفحص بقى على **وسم
# محتوى** يعرّف الصفحة إنها يقين فعلاً، بأي وضع ويب (هبوط أو ويب كامل)، مع حد
# أدنى صغير للحجم ضد التقطيع. وضع الويب بيتغيّر مستقبلاً ⇒ الفحص يفضل صالح.
#
# check <اسم> <رابط> <أدنى حجم> [وسوم مقبولة بمسافات — أي واحد يكفي]
check() {
  name="$1"; url="$2"; min="$3"; marks="${4:-}"
  body=$(mktemp)
  code=000; size=0; mark=-
  for i in 1 2 3; do
    : > "$body"   # من غير التفريغ، محاولة فاشلة بتقرا حجم محاولة قبلها
    code=$(curl -sS -o "$body" -w '%{http_code}' -m 25 "$url" 2>/dev/null) || code=000
    [ -n "$code" ] || code=000
    size=$(wc -c < "$body" 2>/dev/null || echo 0)
    mark=-
    if [ -n "$marks" ]; then
      mark=مفقود
      for m in $marks; do
        if grep -qF -- "$m" "$body" 2>/dev/null; then mark="$m"; break; fi
      done
    fi
    if [ "$code" = "200" ] && [ "$size" -ge "$min" ] && [ "$mark" != "مفقود" ]; then
      echo "✅ $name — $code، ${size} بايت، وسم=$mark (محاولة $i)"
      rm -f "$body"; return 0
    fi
    echo "… $name محاولة $i: كود=$code حجم=$size وسم=$mark"
    [ "$i" -lt 3 ] && sleep 45
  done
  rm -f "$body"
  echo "::error title=$name ساقط::آخر كود=$code حجم=$size وسم=$mark — $url"
  return 1
}

round() {
  fail=0
  # الحد الأدنى للحجم مقصود: ٢٠٠ بصفحة فاضية = سقوط متنكّر. ومع الوسم، ٢٠٠
  # بصفحة خطأ nginx/كلاودفلير (اللي حجمها ممكن يعدّي الحد) بيتكشف كمان.
  check "الموقع getyaqeen.com"      "https://getyaqeen.com/"            20000 "getyaqeen" || fail=1
  # app.getyaqeen.com: وسم صفحة الهبوط (وضع landing) أو باندل Expo (الويب الكامل).
  check "التطبيق app.getyaqeen.com" "https://app.getyaqeen.com/"         1200 "yaqeen-web-build _expo/static" || fail=1
  check "الـAPI api.getyaqeen.com"  "https://api.getyaqeen.com/quiz/daily"  10 '"ok"' || fail=1
  return $fail
}

ROUNDS="${ROUNDS:-18}"
GAP="${GAP:-300}"
n=1
while [ "$n" -le "$ROUNDS" ]; do
  echo "──── نبضة $n/$ROUNDS — $(date -u '+%H:%M:%S UTC')"
  if ! round; then
    echo "::error::يقين ساقط من خارج السيرفر (نبضة $n) — راجع اللوج فوق"
    exit 1
  fi
  n=$((n + 1))
  [ "$n" -le "$ROUNDS" ] && sleep "$GAP"
done
echo "كل الواجهات سليمة طوال $ROUNDS نبضات."
