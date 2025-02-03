WITH
    cte1 AS (
        SELECT
            c.name AS camera_name,
            date_trunc('second', v.started_at)::timestamptz AS started_at,
            jsonb_array_elements(v.detection_summary) AS detection_summary,
            file_name
        FROM
            video v
            INNER JOIN camera c ON c.id = v.camera_id
        WHERE
            v.detection_summary @> '[{"class_name": "person"}]'
            AND started_at > now() - interval '1 day'
    ),
    cte2 AS (
        SELECT
            cte1.started_at,
            cte1.camera_name,
            cte1.detection_summary ->> 'class_name' AS class_name,
            (cte1.detection_summary ->> 'average_score')::numeric AS average_score,
            (cte1.detection_summary ->> 'detected_frame_count')::numeric AS detected_frame_count,
            (cte1.detection_summary ->> 'handled_frame_count')::numeric AS handled_frame_count,
            cte1.file_name
        FROM
            cte1
    ),
    cte3 AS (
        SELECT
            started_at,
            camera_name,
            class_name,
            average_score,
            detected_frame_count,
            handled_frame_count,
            ceil(round(detected_frame_count / handled_frame_count, 2)) AS detected_object_count,
            file_name
        FROM
            cte2
        WHERE
            class_name = 'person'
            AND average_score >= 0.55
            AND detected_frame_count > 20
    ),
    cte4 AS (
        SELECT
            started_at,
            LAG(started_at) OVER (
                PARTITION BY
                    camera_name
                ORDER BY
                    started_at
            ) AS prev_started_at,
            camera_name,
            class_name,
            average_score,
            detected_frame_count,
            handled_frame_count,
            detected_object_count,
            LAG(detected_object_count) OVER (
                PARTITION BY
                    camera_name
                ORDER BY
                    started_at
            ) AS prev_detected_object_count,
            file_name
        FROM
            cte3
    ),
    cte5 AS (
        SELECT
            started_at,
            camera_name,
            class_name,
            average_score,
            detected_frame_count,
            handled_frame_count,
            ceil(round(detected_frame_count / handled_frame_count, 2)) AS detected_object_count,
            file_name,
            CASE
                WHEN (
                    prev_started_at IS NULL
                    OR started_at - prev_started_at > INTERVAL '119 seconds'
                )
                OR (
                    prev_detected_object_count IS null
                    OR detected_object_count > prev_detected_object_count
                ) THEN 1
                ELSE 0
            END AS is_new_event
        FROM
            cte4
    ),
    cte6 AS (
        SELECT
            started_at AT TIME ZONE 'Australia/Perth',
            camera_name,
            class_name,
            average_score,
            detected_frame_count,
            handled_frame_count,
            detected_object_count,
            file_name,
            is_new_event
        FROM
            cte5
        ORDER BY
            started_at DESC
    )
SELECT
    jsonb_agg(cte6)
FROM
    cte6;
