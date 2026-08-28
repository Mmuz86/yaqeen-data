#!/bin/sh
# تتابُع الإشعال (relay) — الخيط بيشعل خليفته بنفسه بدل ما يستنى جدول جيت هَب.
#
# ليه: جدول جيت هَب (schedule) مجهود-أفضل بلا أي ضمان — التوثيق نفسه بيقول إن
# التشغيلات ممكن تتأخّر أو **تتسقط** وقت الحمل. الدرس المقاس على يقين:
#   • 08-26: حلقة ٥٥ دقيقة  → ٣٤.٧٪ بلا تغطية
#   • 08-27: حلقة ٩٠ دقيقة  → فجوة ٢١٨ دقيقة
#   • 08-28: ٣ خيوط بـcron */5 → **صفر** تشغيلة مجدولة في ٣ ساعات (فجوة ٩٤ د)
# تكتير الخيوط أو تقليل الفاصل ما بيحلّش المشكلة لأن كلهم بيعتمدوا على نفس
# المشعِل غير الموثوق. الحل: كل تشغيلة تنادي التشغيلة اللي بعدها بـ
# workflow_dispatch (قناة فورية وموثوقة، مش مجدولة). الـcron بيفضل موجود
# كـ**إعادة إشعال** لو السلسلة اتقطعت (إلغاء/عطل رَنَر).
#
# حارس التكاثر: ما بنشعلش خليفة لو فيه تشغيلة تانية لنفس الخيط قايمة بالفعل
# (queued/in_progress). من غير الحارس ده، الـcron + التتابُع يولّدوا تشغيلات
# متضاعفة أُسّياً — وده على الأغلب اللي خلّى جيت هَب يسقط الجدول أصلاً.
set -u

: "${GH_TOKEN:?}"; : "${GITHUB_REPOSITORY:?}"
: "${WF:?}"          # اسم ملف الوركفلو، مثال uptime.yml
: "${GITHUB_RUN_ID:=0}"
API="https://api.github.com/repos/$GITHUB_REPOSITORY"

api() {
  curl -sS -m 30 -H "Authorization: Bearer $GH_TOKEN" \
       -H "Accept: application/vnd.github+json" \
       -H "X-GitHub-Api-Version: 2022-11-28" "$@"
}

# عدد تشغيلات نفس الخيط القايمة دلوقتي، من غير التشغيلة الحالية.
live=0
for st in queued in_progress; do
  ids=$(api "$API/actions/workflows/$WF/runs?status=$st&per_page=100" \
        | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]\+' \
        | grep -o '[0-9]\+$')
  for id in $ids; do
    [ "$id" = "$GITHUB_RUN_ID" ] && continue
    live=$((live + 1))
  done
done

if [ "$live" -gt 0 ]; then
  echo "⏭️  فيه $live تشغيلة قايمة لـ$WF — مش هنشعل خليفة (منع تكاثر)."
  exit 0
fi

code=$(api -o /tmp/relay.out -w '%{http_code}' -X POST \
       "$API/actions/workflows/$WF/dispatches" \
       -d '{"ref":"main"}')
if [ "$code" = "204" ]; then
  echo "🔁 اتشعلت الخليفة لـ$WF (204)."
else
  # مش بنفشل التشغيلة: الفحص نفسه نجح، والـcron هيعيد الإشعال.
  echo "::warning title=تتابُع الإشعال فشل::$WF كود=$code $(cat /tmp/relay.out 2>/dev/null)"
fi
