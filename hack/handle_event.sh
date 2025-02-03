#!/bin/bash

set -e

CAMERA_ID="${CAMERA_ID?CAMERA_ID env var empty or unset}"
CLASS_NAME="${CLASS_NAME?CLASS_NAME env var empty or unset}"
WEBHOOK_SUFFIX="${WEBHOOK_SUFFIX?WEBHOOK_SUFFIX env var empty or unset}"

while IFS= read -r line; do
    if [[ "${DEBUG}" == "1" ]]; then
        echo -e "\n**** handling event at local system time $(date) ****"
        echo -e "\nline: ${line}"
    fi

    event=$(PAGER=cat PGPASSWORD="${POSTGRES_PASSWORD:-NoNVR!11}" timeout 1 psql -h "${POSTGRES_HOST:-postgres}" -p "${POSTGRES_PORT:-5432}" -U "${POSTGRES_USER:-postgres}" -A -t "${POSTGRES_DB:-camry}" -c "SELECT row_to_json(v) FROM video_with_seen_person v WHERE v.camera_id = '${CAMERA_ID}' AND v.video_id = '$(echo "${line}" | jq -r .object.id)' AND is_new_event = 1;" | jq)

    if [[ $(echo "${event}" | xargs) == "" ]]; then
        if [[ "${DEBUG}" == "1" ]]; then
            echo -e "\nevent: (nil)"
        fi

        continue
    fi

    if [[ "${DEBUG}" == "1" ]]; then
        echo -e "\nevent: ${event}"
    fi

    id=$(echo "${line}" | jq -r '.object.id')
    started_at=$(echo "${line}" | jq -r '.object.started_at')
    ended_at=$(echo "${line}" | jq -r '.object.ended_at')

    file_name=$(echo "${line}" | jq -r '.object.file_name')
    file_url="https://camry.initialed85.cc/media/${file_name}"

    thumbnail_name=$(echo "${line}" | jq -r '.object.thumbnail_name')
    thumbnail_url="https://camry.initialed85.cc/media/${thumbnail_name}"

    camera_id=$(echo "${line}" | jq -r '.object.camera_id')
    camera_name=$(curl -s "https://camry.initialed85.cc/api/cameras?id__eq=${camera_id}" | jq -r .objects[0].name | xargs)
    if [[ "${camera_name}" == "" ]]; then
        camera_name="(unknown)"
    fi

    class_name="$(echo "${event}" | jq -r '.class_name')"
    when="$(echo "${event}" | jq -r '.when')"
    when_h="$(echo "${when}" | cut -c 1-2)"
    when_m="$(echo "${when}" | cut -c 4-5)"
    when_s="$(echo "${when}" | cut -c 7-8)"
    when="${when_h}h${when_m}m${when_s}s"
    # shellcheck disable=SC2001
    when=$(echo "${when}" | sed s/00/0/g)
    detected_object_count="$(echo "${event}" | jq -r '.detected_object_count')"
    started_at_local="$(echo "${event}" | jq -r '.started_at_local' | sed 's/T/ /g')"

    if [[ "${DEBUG}" == "1" ]]; then
        echo -e "\nid: ${id}"
        echo -e "started_at: ${started_at}"
        echo -e "ended_at: ${ended_at}"
        echo -e "file_url: ${file_url}"
        echo -e "thumbnail_url: ${thumbnail_url}"
        echo -e "camera_name: ${camera_name}"
        echo -e "class_name: ${class_name}"
        echo -e "when: ${when}"
        echo -e "detected_object_count: ${detected_object_count}"
        echo -e "started_at_local: ${started_at_local}"
    fi

    data="{
        \"id\": \"${id}\",
        \"started_at\": \"${started_at}\",
        \"ended_at\": \"${ended_at}\",
        \"file_url\": \"${file_url}\",
        \"thumbnail_url\": \"${thumbnail_url}\",
        \"camera_name\": \"${camera_name}\",
        \"class_name\": \"${class_name}\",
        \"when\": \"${when}\",
        \"detected_object_count\": \"${detected_object_count}\",
        \"started_at_local\": \"${started_at_local}\"
    }"

    if ! echo "${data}" | jq >/dev/null 2>&1; then
        echo "${data}" | jq
    fi

    if [[ "${DEBUG}" == "1" ]]; then
        echo -e "\ndata: $(echo "${data}" | jq)"
    fi

    data="$(echo "${data}" | jq)"

    if [[ "${DRY_RUN}" != "1" ]]; then
        if ! curl -vvv -X POST -H 'Content-Type: application/json' -d "${data}" "https://home-assistant.initialed85.cc/api/webhook/camry-object-detected-${WEBHOOK_SUFFIX}"; then
            echo -e "error: webhook call failed"
            continue
        fi
    else
        echo -e "\ndry run: curl -vvv -X POST -H 'Content-Type: application/json' -d \"${data}\" https://home-assistant.initialed85.cc/api/webhook/camry-object-detected-${WEBHOOK_SUFFIX}"
    fi
done

exit 1
