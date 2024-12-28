WITH
    cte1 AS (
        SELECT
            date_trunc('second', v.started_at AT TIME ZONE 'Australia/Darwin') AS started_at,
            jsonb_array_elements(v.detection_summary) AS detection_summary,
            file_name
        FROM
            video v
            INNER JOIN camera c ON c.id = v.camera_id
        WHERE
            c.name = 'Driveway'
            AND v.detection_summary @> '[{"class_name": "person"}]'
    ),
    cte2 AS (
        SELECT
            cte1.started_at,
            cte1.detection_summary ->> 'class_name' AS class_name,
            (cte1.detection_summary ->> 'average_score')::numeric AS average_score,
            (cte1.detection_summary ->> 'weighted_score')::numeric AS weighted_score,
            (cte1.detection_summary ->> 'detected_frame_count')::numeric AS detected_frame_count,
            cte1.file_name
        FROM
            cte1
    )
SELECT
    max(started_at) AS started_at,
    max(class_name) AS class_name,
    round(avg(average_score), 2) AS average_score,
    round(avg(weighted_score), 2) AS weighted_score,
    sum(detected_frame_count) AS detected_frame_count,
    file_name
FROM
    cte2
WHERE
    class_name = 'person'
    AND average_score >= 0.5
    AND detected_frame_count > 5
GROUP BY
    file_name
ORDER BY
    max(cte2.started_at) DESC;
