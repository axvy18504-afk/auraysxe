-- Auralys versi iOS — skema lokal (SQLite ekuivalen dari model SwiftData)
-- Tidak ada server, tidak ada user_id: semua data milik pemilik perangkat.
-- Waktu disimpan sebagai REAL (unix epoch, UTC) — padanan timestamptz untuk app lokal.

create table track (
  id                  text primary key,               -- UUID
  source              text not null check (source in ('imported','folderBookmark','mediaLibrary')),
  file_path           text,                           -- path relatif sandbox / di dalam folder bookmark; null untuk mediaLibrary
  folder_bookmark_id  text references folder_bookmark(id) on delete set null,
  media_persistent_id text,                           -- MPMediaItem.persistentID; null kecuali source='mediaLibrary'
  title               text not null,
  artist              text,
  album               text,
  album_artist        text,
  genre               text,
  duration_sec        real not null default 0,
  format              text not null default 'other',  -- mp3|wav|flac|aac|m4a|other
  file_size           integer,
  artwork_file        text,                           -- nama file di sandbox artwork/, bukan blob
  date_added          real not null,
  play_count          integer not null default 0,
  last_played_at      real,
  is_favorite         integer not null default 0 check (is_favorite in (0,1)),
  is_missing          integer not null default 0 check (is_missing in (0,1)),
  created_at          real not null,
  updated_at          real not null,
  unique (file_path),
  unique (source, media_persistent_id)
);
create index idx_track_album   on track (album, album_artist);
create index idx_track_artist  on track (artist);
create index idx_track_added   on track (date_added desc);
create index idx_track_plays   on track (play_count desc);
create index idx_track_fav     on track (is_favorite) where is_favorite = 1;

create table folder_bookmark (
  id           text primary key,
  bookmark_data blob not null,                        -- security-scoped bookmark
  display_name text not null,
  last_scanned_at real,
  created_at   real not null
);

create table playlist (
  id         text primary key,
  name       text not null,
  created_at real not null,
  updated_at real not null
);

create table playlist_item (
  id          text primary key,
  playlist_id text not null references playlist(id) on delete cascade,
  track_id    text not null references track(id) on delete cascade,
  position    integer not null,
  added_at    real not null,
  unique (playlist_id, track_id),
  unique (playlist_id, position)
);
create index idx_item_playlist on playlist_item (playlist_id, position);

-- Singleton settings: tepat 1 baris, id selalu 'singleton'
create table eq_settings (
  id          text primary key check (id = 'singleton'),
  preset_name text not null default 'Flat',           -- Flat|Classical|Jazz|Rock|Pop|Hip-Hop|Heavy Metal|Custom
  band_gains  text not null default '[]',             -- JSON array gain dB per band
  bass_boost  integer not null default 0 check (bass_boost between 0 and 100),
  reverb      integer not null default 0 check (reverb between 0 and 100),
  virtualizer integer not null default 0 check (virtualizer between 0 and 100),
  updated_at  real not null
);

create table app_settings (
  id                text primary key check (id = 'singleton'),
  visualizer_theme  text not null default 'wave',
  rescan_on_launch  integer not null default 1 check (rescan_on_launch in (0,1)),
  last_scan_at      real,
  resume_track_id   text references track(id) on delete set null,
  resume_position_sec real,
  updated_at        real not null
);

-- View turunan (bukan tabel): Album & Folder dibangun dari track saat query.
-- Album  = select album, album_artist, count(*) ... group by album, album_artist
-- Folder = select folder path dari file_path / folder_bookmark ... group by folder
