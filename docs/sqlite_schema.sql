CREATE TABLE documents (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_url TEXT,
  source_sha256 TEXT NOT NULL UNIQUE,
  source_filename TEXT,
  source_label TEXT,
  document_title TEXT,
  source_unit TEXT,
  created_at TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP),
  updated_at TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP)
);

CREATE TABLE pages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  document_id INTEGER NOT NULL,
  page_number INTEGER NOT NULL,
  ocr_version TEXT NOT NULL,
  extraction_method TEXT NOT NULL DEFAULT 'text_layer' CHECK (extraction_method IN ('text_layer', 'vision_ocr')),
  orientation_degrees INTEGER NOT NULL,
  dpi INTEGER NOT NULL,
  quality_score REAL NOT NULL,
  confidence REAL,
  text_content TEXT NOT NULL,
  normalized_text_content TEXT,
  numeric_sanity_status TEXT,
  created_at TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP),
  updated_at TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP),
  FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE,
  UNIQUE(document_id, page_number, ocr_version)
);

CREATE TABLE page_embeddings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  page_id INTEGER NOT NULL,
  embedding_model_version TEXT NOT NULL,
  embedding_vector BLOB NOT NULL,
  vector_dim INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP),
  FOREIGN KEY(page_id) REFERENCES pages(id) ON DELETE CASCADE,
  UNIQUE(page_id, embedding_model_version)
);
