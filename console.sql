CREATE OR REPLACE TABLE games_data AS
WITH
    unnested_raw AS (
        SELECT
            UNNEST(t1.games) AS game_data_raw
        FROM
         read_json_auto(
             'steam_2025_5k-dataset-games_20250831.json',
             format = 'auto',
             maximum_object_size = 157286400
         ) AS t1
    ),
    unnested_games AS (
        SELECT UNNEST(game_data_raw) FROM unnested_raw
    ),
    unnested_app_details AS (
        SELECT UNNEST(app_details) FROM unnested_games
    ),
    unnested_game_data AS (
        SELECT UNNEST(data) FROM unnested_app_details
    ),
    selected_normalized_data AS (
       SELECT
            steam_appid,
            name AS game_name,
            is_free,
            list_transform(genres, x -> x.description) AS genres,
            metacritic.score AS matacritic_score,
            list_filter(
                [
                    CASE WHEN platforms.windows THEN 'windows' END,
                    CASE WHEN platforms.mac THEN 'mac' END,
                    CASE WHEN platforms.linux THEN 'linux' END
                ],
                x -> x IS NOT NULL
            ) AS supported_platforms,
            release_date.coming_soon AS is_coming_soon,

            -- This piss is vibecoded : )
            CASE WHEN NOT release_date.coming_soon THEN
                TRY_STRPTIME(release_date.date, '%b %d, %Y')::DATE
            ELSE NULL
            END AS normalized_release_date

        FROM
            unnested_game_data
    )
SELECT *
FROM selected_normalized_data;

-- % of free games vs % of paid
SELECT
    CASE WHEN is_free THEN 'Free' ELSE 'Paid' END AS pricing_model,
    COUNT(steam_appid) AS game_count,
    ROUND(COUNT(steam_appid) * 100.0 / SUM(COUNT(steam_appid)) OVER (), 2) AS percentage_of_total
FROM
    games_data
GROUP BY
    is_free
ORDER BY
    game_count DESC
LIMIT 2;

-- Multiplatform support
SELECT
    COUNT(steam_appid) AS total_games,

    SUM(CAST(supported_platforms AS VARCHAR) LIKE '%windows%')::INT AS games_on_windows,
    SUM(CAST(supported_platforms AS VARCHAR) LIKE '%mac%')::INT AS games_on_mac,
    SUM(CAST(supported_platforms AS VARCHAR) LIKE '%linux%')::INT AS games_on_linux,
    SUM(
        CAST(supported_platforms AS VARCHAR) LIKE '%windows%' AND
        CAST(supported_platforms AS VARCHAR) LIKE '%mac%' AND
        CAST(supported_platforms AS VARCHAR) LIKE '%linux%'
    )::INT AS games_on_all_three
FROM
    games_data;

-- Release trend by year
SELECT
    DATE_PART('year', TRY_CAST(normalized_release_date AS DATE)) AS release_year,
    COUNT(steam_appid) AS games_released
FROM
    games_data
WHERE
    release_year IS NOT NULL
GROUP BY
    release_year
ORDER BY
    release_year DESC;

-- Coming Soon vs. Released Status
SELECT
    CASE WHEN is_coming_soon THEN 'Upcoming' ELSE 'Released' END AS game_status,
    COUNT(steam_appid) AS game_count,
    ROUND(COUNT(steam_appid) * 100.0 / SUM(COUNT(steam_appid)) OVER(), 2) AS percentage_of_total
FROM
    games_data
GROUP BY
    is_coming_soon
ORDER BY
    game_count DESC
LIMIT 2;

-- Top 20 games by the metacritic score
SELECT game_name, matacritic_score, genres
FROM games_data
ORDER BY matacritic_score DESC
LIMIT 20;
