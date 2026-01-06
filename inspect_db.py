import sqlite3
import os

# Cross-platform path resolution - resolve relative to script location
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
db_path = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "Serv_ScaI", "scanai.db"))
output_file = os.path.join(SCRIPT_DIR, "db_inspection_result.txt")

with open(output_file, "w", encoding="utf-8") as f:
    if not os.path.exists(db_path):
        f.write(f"Error: Database file not found at {db_path}\n")
        exit()

    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        f.write(f"--- Database: {db_path} ---\n")

        # Get list of tables
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = cursor.fetchall()

        for table in tables:
            table_name = table[0]
            f.write(f"\nTABLE: {table_name}\n")
            
            # Get schema
            cursor.execute(f"PRAGMA table_info({table_name})")
            columns = cursor.fetchall()
            f.write("Schema:\n")
            for col in columns:
                f.write(f"  - {col[1]} ({col[2]})\n")

            # Get sample data
            f.write("Sample Data (First 10 rows):\n")
            cursor.execute(f"SELECT * FROM {table_name} LIMIT 10")
            rows = cursor.fetchall()
            if rows:
                for row in rows:
                    f.write(f"  {row}\n")
            else:
                f.write("  (Empty)\n")

        conn.close()
        print(f"Inspection saved to {output_file}")

    except Exception as e:
        f.write(f"An error occurred: {e}\n")
        print(f"Error: {e}")
