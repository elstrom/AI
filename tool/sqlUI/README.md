# ScanAI Database Manager Pro

Modern SQLite database management UI with full CRUD operations.

## Features

- **🎨 Modern Dark Theme** - Beautiful dark UI with accent colors
- **📊 Table Browser** - View all tables with row counts
- **📋 Data Viewer** - Paginated data view with 100 rows per page
- **🔧 Schema Viewer** - View column details, types, and constraints
- **💻 SQL Query** - Execute any SQL command directly
- **➕ Add Row** - Insert new rows with dialog form
- **✏️ Edit Cell** - Update individual cell values
- **🗑️ Delete Row** - Remove selected rows
- **🔍 Tail View** - View last 10 rows quickly
- **📤 Export** - Export table data to CSV

## Usage

```bash
cd Serv_ScaI/sqlUI
python main.py
```

## Keyboard Shortcuts

- Select table from left panel to view data
- Use pagination buttons to navigate large tables
- Double-click rows to select for editing/deletion

## SQL Query Examples

```sql
-- Select with filter
SELECT * FROM products WHERE price > 1000

-- Update values
UPDATE users SET status = 'active' WHERE id = 1

-- Insert new row
INSERT INTO products (name, price) VALUES ('New Item', 5000)

-- Delete row
DELETE FROM transactions WHERE id = 123

-- Alter table
ALTER TABLE products ADD COLUMN category TEXT
```

## Requirements

- Python 3.8+
- tkinter (included with Python)
- sqlite3 (included with Python)


A standalone Python/Tkinter application for managing the ScanAI SQLite database.

## Features

- **Table Browser**: View all tables in the database
- **Schema View**: Inspect table structure (columns, types, constraints)
- **Data View**: Browse data with pagination
- **Tail View**: Quick view of last N rows (configurable)
- **Inline Editing**: Double-click cells to edit values
- **Export**: Export tables to text/CSV files
- **Print Structure**: Generate database structure report with tail data

## Requirements

- Python 3.8+
- Tkinter (usually included with Python)
- No additional dependencies required

## Installation

No installation required. The application uses only Python standard library.

```bash
# Navigate to the sqlUI folder
cd Serv_ScaI/sqlUI

# Run the application
python main.py
```

## Usage

### Connecting to Database

1. On startup, the app auto-connects to `scanai.db` in the parent folder
2. Use **File → Open Database** to connect to a different database
3. Recent connections are saved and accessible via **File → Recent Connections**

### Browsing Tables

1. Select a table from the left panel
2. Schema is displayed at the top showing column definitions
3. Data is shown below with pagination controls

### Viewing Data

- **All Data**: Shows paginated view of all rows
- **Tail N**: Shows last N rows (useful for recent transactions)
- Use ← → buttons for pagination

### Editing Data

1. Double-click on any cell to edit
2. Enter the new value in the dialog
3. Changes are saved immediately

### Exporting Data

- **Export → Export Current Table**: Save selected table to file
- **Export → Print Database Structure**: Generate full structure report

## Configuration

Settings are stored in `ui_config.json` (auto-created on first run):

```json
{
  "database": {
    "path": "../scanai.db",
    "recent_connections": []
  },
  "ui": {
    "window_width": 1200,
    "window_height": 800,
    "rows_per_page": 50,
    "tail_rows": 10
  }
}
```

### Adjusting Tail Rows

Use **Settings → Set Tail Rows** to change the number of rows shown in tail view.

## File Structure

```
sqlUI/
├── main.py          # Main application
├── config.py        # Configuration management
├── ui_config.json   # User settings (auto-generated)
└── README.md        # This documentation
```

## Screenshots

### Main Interface
```
┌──────────────────────────────────────────────────────────────┐
│ File  Export  Settings  Help                                 │
├────────────┬─────────────────────────────────────────────────┤
│  Tables    │  Schema: products                               │
│  ────────  │  ┌────────┬──────────┬────────┬─────────┬────┐ │
│  products  │  │ Column │ Type     │ NotNull│ Default │ PK │ │
│  pos       │  ├────────┼──────────┼────────┼─────────┼────┤ │
│  users     │  │prod_id │ INTEGER  │ YES    │         │ ✓  │ │
│  trans...  │  │name    │ TEXT     │ YES    │         │    │ │
│            │  └────────┴──────────┴────────┴─────────┴────┘ │
│            │                                                 │
│  ↻ Refresh │  products (156 rows)              Page 1/4  ← →│
│            │  ● All Data  ○ Tail 10                          │
│            │  ┌────────┬──────────┬──────────┬──────────┐   │
│            │  │prod_id │ name     │ price    │ stock    │   │
│            │  ├────────┼──────────┼──────────┼──────────┤   │
│            │  │ 1      │ Cucur    │ 2000     │ 50       │   │
│            │  │ 2      │ Kue Ku   │ 2500     │ 45       │   │
│            │  └────────┴──────────┴──────────┴──────────┘   │
├────────────┴─────────────────────────────────────────────────┤
│ Connected: scanai.db                                         │
└──────────────────────────────────────────────────────────────┘
```

## Troubleshooting

### Database Not Found
- Ensure `scanai.db` exists in `Serv_ScaI/` folder
- Use **File → Open Database** to manually select the database

### Permission Error
- Make sure no other application is using the database
- Check file permissions

### Tkinter Not Found
- On Linux: `sudo apt-get install python3-tk`
- On macOS: Usually included with Python from python.org
- On Windows: Included with standard Python installation

## Cross-Platform Compatibility

The application uses `os.path` for all file operations, ensuring compatibility across:
- Windows
- Linux
- macOS

## License

Part of the ScanAI system.
