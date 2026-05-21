-- =============================================================================
-- Inovação Academy — Dados de referência (seed)
-- Execute DEPOIS de schema.sql
-- =============================================================================

-- point_rules
INSERT INTO public.point_rules (id, event_type, points, is_active) VALUES
    ('e4d83918-9c13-4bad-9324-73d69dacc22b', 'comment_posted',  5,  true),
    ('82baebd4-8b22-49ad-920a-8bb4e93322de', 'comment_replied', 3,  true),
    ('e2aa7c8c-af3a-45bb-94c0-a6fa014ca411', 'video_completed', 20, true),
    ('2e8d822a-c70c-401c-8e94-473ea9e4e439', 'video_watched',   10, true)
ON CONFLICT (event_type) DO NOTHING;

-- badges
INSERT INTO public.badges (id, slug, name, description, icon_url, condition_type, condition_value) VALUES
    ('27bb70a0-f64b-47d7-bac0-be85177464ac', 'first_video',    'Primeiros Passos', 'Assista seu primeiro vídeo',              NULL, 'video_count',      1),
    ('e01b2905-509a-42fd-9fac-8b5f4481eb9d', 'video_5',        'Maratonista',      'Assista 5 vídeos',                        NULL, 'video_count',      5),
    ('def2627b-ebf9-46c7-be86-b34972a1d746', 'first_comment',  'Primeira Voz',     'Poste seu primeiro comentário',           NULL, 'comment_count',    1),
    ('1da01d36-645f-48a8-aca7-893715bfa15d', 'comment_10',     'Participativo',    'Poste 10 comentários',                    NULL, 'comment_count',    10),
    ('12684662-ae00-4482-8e54-26d1ac5b4496', 'streak_7',       'Constante',        'Assista vídeos por 7 dias seguidos',      NULL, 'streak_days',      7),
    ('4f5c94eb-b3a5-460c-8b11-5a1ceb2993e9', 'top3_group',     'Pódio',            'Esteja no top 3 do ranking do seu grupo', NULL, 'ranking_position', 3)
ON CONFLICT (slug) DO NOTHING;
