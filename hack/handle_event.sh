#!/bin/bash

set -e

# websocat ws://camry.initialed85.cc/api/__stream?include=video

while IFS= read -r line; do
    echo -e "**** handling event at local system time $(date) ****\n"

    echo -e "line:\n\n${line}\n"

    event=$(echo "${line}" | jq 'select(.object.detection_summary != []) | select(.object.detection_summary[] | select(.class_name == "person" and .average_score >= 0.55 and .detected_frame_count >= 20))')

    if [[ $(echo "${event}" | xargs) == "" ]]; then
        echo -e "event:\n\n(nil)\n"
        echo -e "this is not a relevant event; skipping...\n"
        continue
    fi

    echo -e "event:\n\n${event}\n"

    echo -e "this is a relevant event; processing...\n"

    id=$(echo "${line}" | jq -r '.object.id')
    started_at=$(echo "$line" | jq -r '.object.started_at')
    ended_at=$(echo "$line" | jq -r '.object.ended_at')

    file_name=$(echo "$line" | jq -r '.object.file_name')
    file_url="https://camry.initialed85.cc/media/${file_name}"

    thumbnail_name=$(echo "$line" | jq -r '.object.thumbnail_name')
    thumbnail_url="https://camry.initialed85.cc/media/${thumbnail_name}"

    camera_name=$(curl -s "https://camry.initialed85.cc/api/videos?id__eq=${id}&camera__load=" | jq -r .objects[0].camera_id_object.name | xargs)
    if [[ "${camera_name}" == "" ]]; then
        camera_name="(unknown)"
    fi

    echo "id: ${id}"
    echo "started_at: ${started_at}"
    echo "ended_at: ${ended_at}"
    echo "file_url: ${file_url}"
    echo "thumbnail_url: ${thumbnail_url}"
    echo "camera_name: ${camera_name}"

    data="{\"id\": \"${id}\", \"started_at\": \"${started_at}\", \"ended_at\": \"${ended_at}\", \"file_url\": \"${file_url}\", \"thumbnail_url\": \"${thumbnail_url}\", \"camera_name\": \"${camera_name}\"}"
    echo "data: ${data}"

    if ! curl -vvv -X POST -H 'Content-Type: application/json' -d "${data}" https://home-assistant.initialed85.cc/api/webhook/camry-person-detected; then
        echo -e "error: webhook call failed\n"
        continue
    fi
done
