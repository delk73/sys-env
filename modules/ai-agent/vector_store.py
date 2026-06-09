#!/home/dce/.local/share/sys-env/ai-venv/bin/python3
import os
import sys
import json
import sqlite3
import argparse
from typing import List, Dict, Any
import numpy as np
import hnswlib
from sentence_transformers import SentenceTransformer

DB_FILE = ".repo_vectors.db"
INDEX_FILE = ".repo_vectors.hnsw"
MODEL_NAME = "all-MiniLM-L6-v2"

class LocalVectorStore:
    def __init__(self, repo_path: str):
        self.repo_path = os.path.abspath(repo_path)
        self.db_path = os.path.join(self.repo_path, DB_FILE)
        self.index_path = os.path.join(self.repo_path, INDEX_FILE)
        
        self.model = SentenceTransformer(MODEL_NAME)
        self.dim = 384
        
        self._init_db()
        self.index = self._init_index()

    def _init_db(self):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS file_chunks (
                    id INTEGER PRIMARY KEY,
                    filepath TEXT NOT NULL,
                    chunk_index INTEGER NOT NULL,
                    content TEXT NOT NULL,
                    UNIQUE(filepath, chunk_index)
                )
            """)
            conn.commit()

    def _init_index(self) -> hnswlib.Index:
        index = hnswlib.Index(space="cosine", dim=self.dim)
        if os.path.exists(self.index_path):
            index.load_index(self.index_path)
        else:
            index.init_index(max_elements=10000, ef_construction=200, M=16)
        return index

    def add_file(self, filepath: str, chunk_size: int = 1000):
        abs_path = os.path.abspath(filepath)
        if not os.path.exists(abs_path):
            return

        with open(abs_path, "r", encoding="utf-8", errors="ignore") as f:
            text = f.read()

        chunks = [text[i:i+chunk_size] for i in range(0, len(text), chunk_size)]
        if not chunks:
            return

        embeddings = self.model.encode(chunks, convert_to_numpy=True)
        
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            for idx, (chunk, embedding) in enumerate(zip(chunks, embeddings)):
                cursor.execute("""
                    INSERT OR REPLACE INTO file_chunks (filepath, chunk_index, content)
                    VALUES (?, ?, ?)
                """, (filepath, idx, chunk))
                row_id = cursor.lastrowid
                self.index.add_items(np.array([embedding]), np.array([row_id]))
            conn.commit()
            
        self.index.save_index(self.index_path)

    def query(self, query_text: str, top_k: int = 3) -> List[Dict[str, Any]]:
        if self.index.element_count == 0:
            return []

        query_vector = self.model.encode([query_text], convert_to_numpy=True)
        labels, distances = self.index.knn_query(query_vector, k=top_k)
        
        results = []
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            for doc_id in labels[0]:
                cursor.execute("SELECT filepath, content FROM file_chunks WHERE id = ?", (int(doc_id),))
                row = cursor.fetchone()
                if row:
                    results.append({"filepath": row[0], "content": row[1]})
        return results

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Local Vector Storage CLI")
    parser.add_argument("--index", type=str, help="File path to chunk and index")
    parser.add_argument("--search", type=str, help="Semantic search query string")
    args = parser.parse_args()

    store = LocalVectorStore(os.getcwd())

    if args.index:
        store.add_file(args.index)
        print(f"Indexed {args.index} successfully.")
    elif args.search:
        hits = store.query(args.search)
        print(json.dumps(hits, indent=2))
