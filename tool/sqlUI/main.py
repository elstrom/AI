"""
ScanAI Database Manager Pro
Modern SQLite database management UI with enhanced UX and Light Theme.
"""

import tkinter as tk
import argparse
import sys
import csv
import json
from tkinter import ttk, messagebox, filedialog, simpledialog
import sqlite3
import os
import json
from datetime import datetime
from config import Config

class DatabaseManager:
    """Core database operations handler."""
    
    def __init__(self, db_path=None):
        self.db_path = db_path
        self.conn = None
        
    def connect(self, db_path):
        try:
            self.close()
            self.db_path = db_path
            self.conn = sqlite3.connect(db_path)
            self.conn.row_factory = sqlite3.Row
            return True
        except sqlite3.Error as e:
            print(f"[ERROR] Connection failed to {db_path}: {e}")
            raise e
        
    def close(self):
        if self.conn:
            self.conn.close()
            self.conn = None
            
    def get_tables(self):
        cursor = self.conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        )
        return [row[0] for row in cursor.fetchall()]
        
    def get_schema(self, table):
        cursor = self.conn.execute(f"PRAGMA table_info('{table}')")
        return cursor.fetchall()
        
    def get_row_count(self, table):
        cursor = self.conn.execute(f"SELECT COUNT(*) FROM '{table}'")
        return cursor.fetchone()[0]
        
    def get_data(self, table, limit=100, offset=0, search_query=None):
        base_query = f"SELECT * FROM '{table}'"
        params = []
        
        if search_query:
            # Simple global search across all text columns unlikely to be performant for huge datasets,
            # but good for UX on smaller ones.
            # For simplicity, we just filter by the first few text columns or ID.
            schema = self.get_schema(table)
            search_clauses = []
            for col in schema:
                # col[1] is name
                search_clauses.append(f"CAST(\"{col[1]}\" AS TEXT) LIKE ?")
                params.append(f"%{search_query}%")
            
            if search_clauses:
                base_query += " WHERE " + " OR ".join(search_clauses)

        query = f"{base_query} LIMIT {limit} OFFSET {offset}"
        
        # Need to handle params carefully if limit/offset are separate
        # SQLite doesn't support parameterized LIMIT/OFFSET easily in this string builder context usually,
        # but execute handles it.
        # Actually simplest is to format limit/offset directly as they are ints controlled by us.
        
        cursor = self.conn.execute(query, params)
        if cursor.description:
            columns = [desc[0] for desc in cursor.description]
            return columns, cursor.fetchall()
        return [], []
        
    def get_tail(self, table, rows=10):
        cursor = self.conn.execute(f"SELECT * FROM '{table}' ORDER BY rowid DESC LIMIT {rows}")
        columns = [desc[0] for desc in cursor.description]
        return columns, list(reversed(cursor.fetchall()))
        
    def execute_query(self, query):
        cursor = self.conn.execute(query)
        self.conn.commit()
        if cursor.description:
            columns = [desc[0] for desc in cursor.description]
            return columns, cursor.fetchall()
        return None, cursor.rowcount
        
    def insert_row(self, table, data):
        try:
            cols = ', '.join(f"\"{k}\"" for k in data.keys())
            placeholders = ', '.join(['?' for _ in data])
            query = f"INSERT INTO \"{table}\" ({cols}) VALUES ({placeholders})"
            self.conn.execute(query, list(data.values()))
            self.conn.commit()
        except sqlite3.Error as e:
            print(f"[ERROR] INSERT failed in table '{table}': {e}")
            print(f"Query: {query} Params: {list(data.values())}")
            raise e

    def update_cell(self, table, pk_col, pk_val, col, new_val):
        try:
            query = f"UPDATE \"{table}\" SET \"{col}\"=? WHERE \"{pk_col}\"=?"
            self.conn.execute(query, (new_val, pk_val))
            self.conn.commit()
        except sqlite3.Error as e:
            print(f"[ERROR] UPDATE failed in table '{table}': {e}")
            print(f"Query: {query} Params: {(new_val, pk_val)}")
            raise e

    def delete_row(self, table, pk_col, pk_val):
        try:
            query = f"DELETE FROM \"{table}\" WHERE \"{pk_col}\"=?"
            self.conn.execute(query, (pk_val,))
            self.conn.commit()
        except sqlite3.Error as e:
            print(f"[ERROR] DELETE failed in table '{table}': {e}")
            print(f"Query: {query} Param: {pk_val}")
            raise e


class ModernTheme:
    """Neo-Tech Light Theme."""
    BG = "#F0F2F5"           # Cloud White
    BG_SECONDARY = "#FFFFFF" # Pure White
    BG_TERTIARY = "#DFE6E9"  # Soft Gray
    
    FG = "#2D3436"           # Jet Black (High Contrast)
    FG_LIGHT = "#636E72"     # Muted Gray
    FG_INVERT = "#FFFFFF"    # White text for dark headers/buttons
    
    ACCENT = "#6C5CE7"       # Electric Violet (Futuristic)
    ACCENT_HOVER = "#a29bfe" # Soft Purple
    
    SUCCESS = "#00b894"      # Mint Green
    WARNING = "#fdcb6e"      # Sunflower
    ERROR = "#d63031"        # Omni Red
    
    SELECTION = "#e1dbff"    # Very light purple selection
    SELECTION_FG = "#2d3436" # Keep text dark on selection
    

class MainApp(tk.Tk):
    def __init__(self, db_path=None):
        super().__init__()
        self.title("ScanAI Database Manager Pro")
        self.geometry("1300x850")
        self.configure(bg=ModernTheme.BG)
        
        self.config = Config()
        if db_path:
            self.config.db_path = db_path
            
        self.db = DatabaseManager()
        self.current_table = None
        self.current_page = 0
        self.search_var = tk.StringVar()
        
        self._setup_styles()
        self._create_menu()
        self._create_ui()
        self._auto_connect()
        
    def _setup_styles(self):
        style = ttk.Style()
        style.theme_use('clam')
        
        # General
        style.configure(".", background=ModernTheme.BG, foreground=ModernTheme.FG, font=('Segoe UI', 10))
        style.configure("TFrame", background=ModernTheme.BG)
        style.configure("White.TFrame", background=ModernTheme.BG_SECONDARY)
        
        # Labels
        style.configure("TLabel", background=ModernTheme.BG, foreground=ModernTheme.FG, font=('Segoe UI', 10))
        style.configure("Title.TLabel", font=('Segoe UI', 18, 'bold'), foreground=ModernTheme.ACCENT)
        style.configure("Status.TLabel", font=('Consolas', 9), foreground=ModernTheme.FG_LIGHT)
        
        # Buttons (Futuristic Flat Style)
        style.configure("TButton", 
                       background=ModernTheme.BG_SECONDARY, 
                       foreground=ModernTheme.FG, 
                       font=('Segoe UI', 9, 'bold'), 
                       borderwidth=0,
                       relief="flat",
                       padding=8)
        style.map("TButton", 
                 background=[('active', ModernTheme.BG_TERTIARY), ('pressed', ModernTheme.ACCENT)], 
                 foreground=[('pressed', ModernTheme.FG_INVERT)])
                 
        # Accent Button (Primary Action)
        style.configure("Accent.TButton", 
                       background=ModernTheme.ACCENT, 
                       foreground=ModernTheme.FG_INVERT,
                       font=('Segoe UI', 9, 'bold'),
                       borderwidth=0)
        style.map("Accent.TButton", 
                 background=[('active', ModernTheme.ACCENT_HOVER)])

        # Entry
        style.configure("TEntry", 
                       fieldbackground="white", 
                       foreground=ModernTheme.FG,
                       borderwidth=0,
                       relief="flat",
                       padding=8)
                       
        # Treeview (The Data Grid)
        style.configure("Treeview", 
                       background="white", 
                       foreground=ModernTheme.FG, 
                       fieldbackground="white", 
                       rowheight=32,
                       font=('Segoe UI', 10),
                       borderwidth=0)
        
        # Dark Header for "Tech" contrast
        style.configure("Treeview.Heading", 
                       background=ModernTheme.FG, 
                       foreground=ModernTheme.FG_INVERT, 
                       font=('Segoe UI', 10, 'bold'),
                       relief="flat",
                       padding=8)
        style.map("Treeview.Heading",
                  background=[('active', ModernTheme.ACCENT)])
                       
        style.map("Treeview", 
                 background=[('selected', ModernTheme.SELECTION)], 
                 foreground=[('selected', ModernTheme.SELECTION_FG)])
                 
        # Notebook (Tabs)
        style.configure("TNotebook", background=ModernTheme.BG, borderwidth=0)
        style.configure("TNotebook.Tab", 
                       background=ModernTheme.BG, 
                       foreground=ModernTheme.FG_LIGHT, 
                       padding=[20, 8], 
                       font=('Segoe UI', 11))
        style.map("TNotebook.Tab", 
                 background=[('selected', ModernTheme.BG_SECONDARY)],
                 foreground=[('selected', ModernTheme.ACCENT)],
                 font=[('selected', ('Segoe UI', 11, 'bold'))],
                 focuscolor=[('selected', 'none')]) # Remove dotted line

    def _create_menu(self):
        menubar = tk.Menu(self, bg=ModernTheme.BG_SECONDARY, fg=ModernTheme.FG)
        
        file_menu = tk.Menu(menubar, tearoff=0, bg=ModernTheme.BG_SECONDARY, fg=ModernTheme.FG)
        file_menu.add_command(label="Open Database...", command=self._open_db)
        file_menu.add_command(label="📄 Generate Full DB Report...", command=self._generate_report)
        file_menu.add_separator()
        file_menu.add_command(label="Exit", command=self.quit)
        menubar.add_cascade(label="File", menu=file_menu)
        
        self.configure(menu=menubar)
        
    def _create_ui(self):
        # Top Status/Connection Bar
        top_bar = ttk.Frame(self, padding="10 5")
        top_bar.pack(fill=tk.X)
        self.db_label = ttk.Label(top_bar, text="No Database Open", font=('Segoe UI', 10, 'bold'))
        self.db_label.pack(side=tk.LEFT)
        
        # Main PanedWindow (Split Layout)
        self.paned = ttk.PanedWindow(self, orient=tk.HORIZONTAL)
        self.paned.pack(fill=tk.BOTH, expand=True, padx=10, pady=(0, 10))
        
        # --- LEFT PANEL: Table List ---
        left_panel = ttk.Frame(self.paned, style="White.TFrame", padding=10)
        self.paned.add(left_panel, weight=1)
        
        ttk.Label(left_panel, text="TABLES", font=('Segoe UI', 9, 'bold'), foreground=ModernTheme.FG_LIGHT).pack(anchor='w', pady=(0, 5))
        
        list_scroll = ttk.Scrollbar(left_panel)
        list_scroll.pack(side=tk.RIGHT, fill=tk.Y)
        
        self.table_list = tk.Listbox(left_panel, 
                                      bg="white", 
                                      fg=ModernTheme.FG, 
                                      selectbackground=ModernTheme.SELECTION,
                                      selectforeground=ModernTheme.SELECTION_FG,
                                      font=('Segoe UI', 11),
                                      borderwidth=0, 
                                      highlightthickness=0,
                                      activestyle='none',
                                      yscrollcommand=list_scroll.set)
        self.table_list.pack(fill=tk.BOTH, expand=True)
        list_scroll.config(command=self.table_list.yview)
        self.table_list.bind('<<ListboxSelect>>', self._on_table_select)
        
        ttk.Button(left_panel, text="🔄 Refresh Tables", command=self._refresh_tables).pack(fill=tk.X, pady=(10, 0))
        
        # --- RIGHT PANEL: Content ---
        right_panel = ttk.Frame(self.paned, padding=(10, 0, 0, 0))
        self.paned.add(right_panel, weight=4)
        
        # Header Area
        header_frame = ttk.Frame(right_panel)
        header_frame.pack(fill=tk.X, pady=(0, 10))
        
        self.table_title = ttk.Label(header_frame, text="Select a Table", style="Title.TLabel")
        self.table_title.pack(side=tk.LEFT)
        
        # Search Box
        search_frame = ttk.Frame(header_frame)
        search_frame.pack(side=tk.RIGHT)
        ttk.Label(search_frame, text="🔍").pack(side=tk.LEFT, padx=(0, 5))
        self.search_entry = ttk.Entry(search_frame, textvariable=self.search_var, width=25)
        self.search_entry.pack(side=tk.LEFT)
        self.search_entry.bind('<Return>', lambda e: self._load_data())
        ttk.Button(search_frame, text="List", command=self._load_data, width=4).pack(side=tk.LEFT, padx=(5,0))
        
        # Tabs
        self.notebook = ttk.Notebook(right_panel)
        self.notebook.pack(fill=tk.BOTH, expand=True)
        
        # 1. Data Tab
        data_tab = ttk.Frame(self.notebook, style="White.TFrame")
        self.notebook.add(data_tab, text="  📊 Data  ")
        
        # Toolbar inside Data Tab
        toolbar = ttk.Frame(data_tab, style="White.TFrame", padding=5)
        toolbar.pack(fill=tk.X)
        
        ttk.Button(toolbar, text="➕ Add Row", command=self._add_row).pack(side=tk.LEFT, padx=2)
        ttk.Button(toolbar, text="✏️ Edit", command=self._edit_cell).pack(side=tk.LEFT, padx=2)
        ttk.Button(toolbar, text="🗑️ Delete", command=self._delete_row).pack(side=tk.LEFT, padx=2)
        
        ttk.Separator(toolbar, orient=tk.VERTICAL).pack(side=tk.LEFT, fill=tk.Y, padx=10)
        
        ttk.Button(toolbar, text="⏮️", width=3, command=self._prev_page).pack(side=tk.LEFT, padx=2)
        self.page_label = ttk.Label(toolbar, text="Page 1", width=15, anchor="center", background="white")
        self.page_label.pack(side=tk.LEFT, padx=5)
        ttk.Button(toolbar, text="⏭️", width=3, command=self._next_page).pack(side=tk.LEFT, padx=2)
        
        # Tail 10 button removed as requested
        
        # Data Grid
        tree_frame = ttk.Frame(data_tab)
        tree_frame.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)
        
        self.data_tree = ttk.Treeview(tree_frame, show='headings', selectmode='extended')
        vsb = ttk.Scrollbar(tree_frame, orient="vertical", command=self.data_tree.yview)
        hsb = ttk.Scrollbar(tree_frame, orient="horizontal", command=self.data_tree.xview)
        self.data_tree.configure(yscrollcommand=vsb.set, xscrollcommand=hsb.set)
        
        self.data_tree.grid(row=0, column=0, sticky='nsew')
        vsb.grid(row=0, column=1, sticky='ns')
        hsb.grid(row=1, column=0, sticky='ew')
        tree_frame.grid_rowconfigure(0, weight=1)
        tree_frame.grid_columnconfigure(0, weight=1)
        
        # Bindings
        self.data_tree.bind('<Double-1>', lambda e: self._edit_cell())
        self.data_tree.bind('<Button-3>', self._show_context_menu) # Right click
        
        # Zebra striping tag
        self.data_tree.tag_configure('even', background='white')
        self.data_tree.tag_configure('odd', background=ModernTheme.BG)
        
        # 2. Schema Tab
        schema_tab = ttk.Frame(self.notebook, style="White.TFrame", padding=10)
        self.notebook.add(schema_tab, text="  🔧 Structure  ")
        
        self.schema_tree = ttk.Treeview(schema_tab, columns=('name', 'type', 'notnull', 'pk'), show='headings')
        self.schema_tree.heading('name', text='Column Name')
        self.schema_tree.heading('type', text='Type')
        self.schema_tree.heading('notnull', text='Not Null?')
        self.schema_tree.heading('pk', text='Primary Key')
        self.schema_tree.column('name', width=200)
        self.schema_tree.column('type', width=100)
        self.schema_tree.column('notnull', width=80, anchor='center')
        self.schema_tree.column('pk', width=80, anchor='center')
        self.schema_tree.pack(fill=tk.BOTH, expand=True)
        
        # 3. Query Tab
        query_tab = ttk.Frame(self.notebook, style="White.TFrame", padding=10)
        self.notebook.add(query_tab, text="  💻 SQL Query  ")
        
        ttk.Label(query_tab, text="Execute arbitrary SQL queries:", background="white").pack(anchor='w')
        self.query_text = tk.Text(query_tab, height=6, 
                                   font=('Consolas', 11),
                                   bg=ModernTheme.BG,
                                   fg=ModernTheme.FG,
                                   borderwidth=1,
                                   relief="solid")
        self.query_text.pack(fill=tk.X, pady=5)
        
        btn_frame = ttk.Frame(query_tab, style="White.TFrame")
        btn_frame.pack(fill=tk.X, pady=5)
        ttk.Button(btn_frame, text="▶️ Run Query", command=self._execute_query, style="Accent.TButton").pack(side=tk.RIGHT)
        ttk.Button(btn_frame, text="Clear", command=lambda: self.query_text.delete('1.0', tk.END)).pack(side=tk.RIGHT, padx=5)
        
        self.result_tree = ttk.Treeview(query_tab, show='headings')
        self.result_tree.pack(fill=tk.BOTH, expand=True, pady=(5, 0))
        
        # Status footer
        self.status = ttk.Label(self, text="Ready", style="Status.TLabel", anchor="e")
        self.status.pack(fill=tk.X, padx=10, pady=5)
        
        # Context Menu
        self.context_menu = tk.Menu(self, tearoff=0, bg="white", fg=ModernTheme.FG)
        self.context_menu.add_command(label="✏️ Edit Cell", command=self._edit_cell)
        self.context_menu.add_command(label="🗑️ Delete Row", command=self._delete_row)
        self.context_menu.add_separator()
        self.context_menu.add_command(label="📋 Copy Value", command=self._copy_cell_value)

    def _show_context_menu(self, event):
        item = self.data_tree.identify_row(event.y)
        if item:
            self.data_tree.selection_set(item)
            self.context_menu.post(event.x_root, event.y_root)

    def _auto_connect(self):
        if self.config.db_path and os.path.exists(self.config.db_path):
            try:
                self.db.connect(self.config.db_path)
                self._refresh_tables()
                self._update_db_label(self.config.db_path)
            except Exception as e:
                self._set_status(f"Auto-connect failed: {e}")
                
    def _open_db(self):
        path = filedialog.askopenfilename(filetypes=[("SQLite", "*.db"), ("All", "*.*")])
        if path:
            try:
                self.db.connect(path)
                self.config.db_path = path
                self._refresh_tables()
                self._update_db_label(path)
            except Exception as e:
                messagebox.showerror("Error", str(e))
                
    def _update_db_label(self, path):
        filename = os.path.basename(path)
        self.db_label.config(text=f"📂 {filename}")
        self._set_status(f"Connected to {path}")

    def _refresh_tables(self):
        try:
            self.table_list.delete(0, tk.END)
            if self.db.conn:
                tables = self.db.get_tables()
                for table in tables:
                    row_count = self.db.get_row_count(table)
                    self.table_list.insert(tk.END, f"{table} ({row_count})")
        except Exception as e:
            print(f"[ERROR] _refresh_tables failed: {e}")
            messagebox.showerror("Refresh Error", f"Failed to refresh table list:\n{e}")
                
    def _on_table_select(self, event):
        sel = self.table_list.curselection()
        if sel:
            raw_text = self.table_list.get(sel[0])
            table = raw_text.rsplit(' (', 1)[0]
            self.current_table = table
            self.current_page = 0
            self.search_var.set("") # Clear search
            self.table_title.config(text=f"📊 {table}")
            self._load_data()
            self._load_schema()
            
    def _load_data(self):
        if not self.current_table:
            return
        
        try:
            search = self.search_var.get().strip()
            cols, rows = self.db.get_data(
                self.current_table, 
                limit=self.config.rows_per_page, 
                offset=self.current_page * self.config.rows_per_page,
                search_query=search
            )
            
            self._populate_tree(self.data_tree, cols, rows)
            
            # Update page label
            if not search:
                total = self.db.get_row_count(self.current_table)
                start = self.current_page * self.config.rows_per_page + 1
                end = min(start + len(rows) - 1, total)
                if total == 0:
                    self.page_label.config(text="No Data")
                else:
                    self.page_label.config(text=f"{start}-{end} of {total}")
            else:
                self.page_label.config(text=f"Found {len(rows)} matches")
        except Exception as e:
            print(f"[ERROR] _load_data failed for '{self.current_table}': {e}")
            messagebox.showerror("Data Load Error", f"Failed to load data for '{self.current_table}':\n{e}")
        
    def _load_schema(self):
        if not self.current_table:
            return
        try:
            self.schema_tree.delete(*self.schema_tree.get_children())
            schema = self.db.get_schema(self.current_table)
            for i, col in enumerate(schema):
                tag = 'odd' if i % 2 else 'even'
                self.schema_tree.insert('', tk.END, values=(col[1], col[2], '❌' if col[3] else '✔', '🔑' if col[5] else ''), tags=(tag,))
        except Exception as e:
            print(f"[ERROR] Failed to load schema for '{self.current_table}': {e}")
            messagebox.showerror("Schema Error", f"Failed to load structure for '{self.current_table}':\n{e}")
            
    def _populate_tree(self, tree, cols, rows):
        tree.delete(*tree.get_children())
        tree['columns'] = cols
        
        # Calculate optimal column width (simple heuristic)
        for col in cols:
            tree.heading(col, text=col)
            tree.column(col, width=120, minwidth=50)
            
        for i, row in enumerate(rows):
            tag = 'odd' if i % 2 else 'even'
            # Convert None/Null to text
            safe_row = ['<NULL>' if val is None else val for val in row]
            tree.insert('', tk.END, values=safe_row, tags=(tag,))
            
    def _prev_page(self):
        if self.current_page > 0:
            self.current_page -= 1
            self._load_data()
            
    def _next_page(self):
        # We don't know total matches in search mode easily without extra count query, 
        # but for normal mode we do. Simple next:
        self.current_page += 1
        self._load_data()
        # If no data returned, load data will show empty list, maybe better UX handled inside load_data
        
    def _generate_report(self):
        if not self.db.conn:
             messagebox.showwarning("Report", "No database connected.")
             return
             
        path = filedialog.asksaveasfilename(
            defaultextension=".txt", 
            filetypes=[("Text Report", "*.txt"), ("All Files", "*.*")],
            initialfile=f"db_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
        )
        
        if path:
            try:
                with open(path, 'w', encoding='utf-8') as f:
                    f.write("="*60 + "\n")
                    f.write(f"SCANAI DATABASE REPORT\n")
                    f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
                    f.write(f"Database: {self.config.db_path}\n")
                    f.write("="*60 + "\n\n")
                    
                    tables = self.db.get_tables()
                    for table in tables:
                        count = self.db.get_row_count(table)
                        f.write(f"\nTABLE: {table} (Rows: {count})\n")
                        f.write("-" * 40 + "\n")
                        
                        # Schema
                        f.write("SCHEMA:\n")
                        schema = self.db.get_schema(table)
                        for col in schema:
                            # name, type, notnull, pk
                            pk_str = " [PK]" if col[5] else ""
                            nn_str = " NOT NULL" if col[3] else ""
                            f.write(f"  - {col[1]} ({col[2]}){nn_str}{pk_str}\n")
                        
                        # Data (Tail 10)
                        f.write("\nLATEST DATA (Tail 10):\n")
                        try:
                            t_cols, t_rows = self.db.get_tail(table, 10)
                            if not t_rows:
                                f.write("  (Table is empty)\n")
                            else:
                                # Header
                                f.write("  " + " | ".join(t_cols) + "\n")
                                for row in t_rows:
                                    s_row = [str(val) for val in row]
                                    f.write("  " + " | ".join(s_row) + "\n")
                        except Exception as e:
                            f.write(f"  (Error reading data: {e})\n")
                            
                        f.write("\n" + "="*60 + "\n")
                        
                self._set_status(f"Report report generated: {path}")
                messagebox.showinfo("Success", f"Database report saved to:\n{path}")
                
            except Exception as e:
                messagebox.showerror("Export Error", str(e))
            
    def _add_row(self):
        if not self.current_table:
            messagebox.showwarning("Warning", "Please select a table first")
            return
        try:
            schema = self.db.get_schema(self.current_table)
            dialog = AddRowDialog(self, schema)
            self.wait_window(dialog) # WAIT FOR DIALOG TO CLOSE
            
            if dialog.result:
                self.db.insert_row(self.current_table, dialog.result)
                self._load_data()
                self._refresh_tables()
                self._set_status("Row added successfully")
        except Exception as e:
            print(f"[ERROR] _add_row failed: {e}")
            messagebox.showerror("Add Row Error", f"Failed to add row to '{self.current_table}':\n{e}")
                
    def _copy_cell_value(self):
        sel = self.data_tree.selection()
        if not sel: return
        
        # Identify column under mouse is hard in treeview via menu click w/o event
        # We copy Selected Row's first value or something? 
        # Better: Copy the whole row representation
        item = self.data_tree.item(sel[0])
        val = str(item['values'])
        self.clipboard_clear()
        self.clipboard_append(val)
        self._set_status("Row copied to clipboard")

    def _edit_cell(self):
        sel = self.data_tree.selection()
        if not sel:
            print("[DEBUG ERROR] _edit_cell: No row selected")
            messagebox.showwarning("Warning", "Please select a row to edit")
            return
        if not self.current_table:
            print("[DEBUG ERROR] _edit_cell: No table selected")
            return
            
        try:
            item = self.data_tree.item(sel[0])
            cols = self.data_tree['columns']
            
            # Primary key detection
            schema = self.db.get_schema(self.current_table)
            pk_candidates = [c[1] for c in schema if c[5]]
            
            if pk_candidates:
                pk_col = pk_candidates[0]
            else:
                # Fallback to 'id' if exists in columns
                if 'id' in [c.lower() for c in cols]:
                    pk_col = [c for c in cols if c.lower() == 'id'][0]
                else:
                    messagebox.showwarning("Edit Warning", 
                        f"Table '{self.current_table}' has no Primary Key.\n"
                        "Editing might not work correctly.")
                    pk_col = cols[0] if cols else None
            
            pk_idx = -1
            if pk_col and pk_col in cols:
                pk_idx = cols.index(pk_col)
            
            pk_val = item['values'][pk_idx] if pk_idx != -1 else None

            if not pk_col:
                messagebox.showerror("Error", "No columns available to identify this row.")
                return

            col = simpledialog.askstring("Edit Value", f"Enter Column Name to Edit:\nAvailable: {', '.join(cols)}")
            if col:
                if col not in cols:
                    messagebox.showerror("Error", f"Column '{col}' not found in table.")
                    return
                    
                current_val = item['values'][cols.index(col)]
                new_val = simpledialog.askstring("Edit Value", f"Edit value for '{col}' (ID: {pk_val}):", initialvalue=current_val)
                if new_val is not None:
                    self.db.update_cell(self.current_table, pk_col, pk_val, col, new_val)
                    self._load_data()
                    self._set_status("Cell updated successfully")
        except Exception as e:
            print(f"[ERROR] _edit_cell failed: {e}")
            messagebox.showerror("Update Error", f"Failed to update cell:\n{e}")
                    
    def _delete_row(self):
        sel = self.data_tree.selection()
        if not sel:
            print("[DEBUG ERROR] _delete_row: No row selected")
            messagebox.showwarning("Warning", "Please select a row to delete")
            return
        if not self.current_table:
            return
            
        if not messagebox.askyesno("Confirm Delete", f"Are you sure you want to delete {len(sel)} selected row(s)?"):
            return
            
        try:
            cols = self.data_tree['columns']
            schema = self.db.get_schema(self.current_table)
            pk_candidates = [c[1] for c in schema if c[5]]
            pk_col = pk_candidates[0] if pk_candidates else (cols[0] if cols else None)
            
            if not pk_col or pk_col not in cols:
                print(f"[DEBUG ERROR] Cannot determine Primary Key for delete in {self.current_table}")
                messagebox.showerror("Delete Error", "Cannot determine Primary Key to perform delete.")
                return
                
            pk_idx = cols.index(pk_col)
            count = 0
            for s in sel:
                item = self.data_tree.item(s)
                pk_val = item['values'][pk_idx]
                self.db.delete_row(self.current_table, pk_col, pk_val)
                count += 1
            self._load_data()
            self._refresh_tables()
            self._set_status(f"Deleted {count} row(s)")
        except Exception as e:
            print(f"[ERROR] _delete_row failed: {e}")
            messagebox.showerror("Delete Error", f"Failed to delete row(s):\n{e}")
            
    def _execute_query(self):
        query = self.query_text.get("1.0", tk.END).strip()
        if not query:
            return
        try:
            cols, result = self.db.execute_query(query)
            if cols:
                self._populate_tree(self.result_tree, cols, result)
                self._set_status(f"Query returned {len(result)} rows")
            else:
                self.result_tree.delete(*self.result_tree.get_children())
                self._set_status(f"Query executed successfully. Affected rows: {result}")
            self._refresh_tables()
        except Exception as e:
            print(f"[ERROR] SQL query failed: {e}")
            print(f"Statement: {query}")
            messagebox.showerror("Query Error", f"SQL Execution Failed:\n{e}")

    def _set_status(self, msg):
        self.status.config(text=f"ℹ️ {datetime.now().strftime('%H:%M:%S')} - {msg}")


class AddRowDialog(tk.Toplevel):
    def __init__(self, parent, schema):
        super().__init__(parent)
        self.title("Add New Row")
        self.geometry("400x500")
        self.configure(bg=ModernTheme.BG)
        self.result = None
        self.entries = {}
        
        main_frame = ttk.Frame(self, padding=20)
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        ttk.Label(main_frame, text="Insert Data", style="Title.TLabel").pack(pady=(0, 20))
        
        form_frame = ttk.Frame(main_frame)
        form_frame.pack(fill=tk.BOTH, expand=True)
        
        # Scrollable form if too many columns
        canvas = tk.Canvas(form_frame, bg=ModernTheme.BG, highlightthickness=0)
        scrollbar = ttk.Scrollbar(form_frame, orient="vertical", command=canvas.yview)
        scrollable_frame = ttk.Frame(canvas, style="TFrame")
        
        scrollable_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )
        
        canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)
        
        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        
        for i, col in enumerate(schema):
            # col[1] = name, col[2] = type, col[5] = is_pk
            label_text = f"{col[1]} ({col[2]})"
            if col[5]: label_text += " [PK]"
            
            lbl = ttk.Label(scrollable_frame, text=label_text)
            lbl.pack(anchor='w', pady=(5, 0))
            
            entry = ttk.Entry(scrollable_frame, width=40)
            # Placeholder for Auto-Increment PK
            if col[5] and 'INT' in col[2].upper():
                entry.insert(0, "(Auto)")
                
            entry.pack(fill=tk.X, pady=(0, 10))
            self.entries[col[1]] = entry
            
        btn_frame = ttk.Frame(main_frame)
        btn_frame.pack(fill=tk.X, pady=20)
        
        ttk.Button(btn_frame, text="Cancel", command=self.destroy).pack(side=tk.RIGHT, padx=5)
        ttk.Button(btn_frame, text="Save Row", style="Accent.TButton", command=self._submit).pack(side=tk.RIGHT)
        
        self.transient(parent)
        self.grab_set()
        self.parent = parent
        
    def _submit(self):
        try:
            data = {}
            for col, entry in self.entries.items():
                val = entry.get().strip()
                if val and val != "(Auto)":
                    data[col] = val
            
            if not data:
                messagebox.showwarning("Warning", "Please enter at least one value.")
                return
                
            self.result = data
            self.destroy()
        except Exception as e:
            print(f"[ERROR] AddRowDialog _submit failed: {e}")
            messagebox.showerror("Error", f"Failed to prepare data:\n{e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="ScanAI Database Manager Pro")
    parser.add_argument("db_path", nargs="?", help="Path to SQLite database file")
    parser.add_argument("-q", "--query", help="Execute SQL query directly and exit (Headless mode)")
    parser.add_argument("-o", "--output", help="Output file path (CSV or JSON) for query results")
    parser.add_argument("--format", choices=['table', 'csv', 'json'], default='table', help="Output format (default: table)")
    
    args = parser.parse_args()
    
    # Configuration setup
    config = Config()
    target_db = args.db_path if args.db_path else config.db_path
    
    # Validasi path database
    if not target_db or not os.path.exists(target_db):
        if args.query:
            print(f"Error: Database file not found at '{target_db}'")
            print("Please specify db_path: python main.py <db_path> -q <query>")
            sys.exit(1)
            
    # --- HEADLESS / CLI MODE ---
    if args.query:
        if not target_db:
            print("Error: No database specified.")
            sys.exit(1)
            
        try:
            # Setup minimal DB connection (bypass GUI)
            db = DatabaseManager()
            db.connect(target_db)
            
            # Execute
            cols, rows = db.execute_query(args.query)
            
            # Handle non-SELECT queries
            if cols is None:
                print(f"Success: Query affected {rows} rows.")
                sys.exit(0)
                
            # Handle SELECT results
            results = []
            if args.format == 'json':
                for row in rows:
                    results.append(dict(zip(cols, row)))
            else:
                # Convert all to list of strings/values
                results = [list(row) for row in rows]

            # Output Handling
            if args.output:
                with open(args.output, 'w', newline='', encoding='utf-8') as f:
                    if args.output.endswith('.json') or args.format == 'json':
                        json.dump(results, f, indent=2, default=str)
                    else: # CSV default for file
                        writer = csv.writer(f)
                        writer.writerow(cols)
                        writer.writerows(results)
                print(f"Results saved to {args.output}")
                
            else:
                # Print to Console
                if args.format == 'json':
                    print(json.dumps(results, indent=2, default=str))
                elif args.format == 'csv':
                    writer = csv.writer(sys.stdout)
                    writer.writerow(cols)
                    writer.writerows(results)
                else:
                    # Pretty Table Output
                    # Calculate widths
                    widths = [len(c) for c in cols]
                    for row in results:
                        for i, val in enumerate(row):
                            widths[i] = max(widths[i], len(str(val)))
                    
                    # Print Header
                    header = " | ".join(f"{c:<{w}}" for c, w in zip(cols, widths))
                    print("-" * len(header))
                    print(header)
                    print("-" * len(header))
                    
                    # Print Rows
                    for row in results:
                        print(" | ".join(f"{str(v):<{w}}" for v, w in zip(row, widths)))
                        
        except Exception as e:
            print(f"Error executing query: {e}")
            sys.exit(1)
            
    else:
        # --- GUI MODE ---
        app = MainApp(db_path=args.db_path)
        app.mainloop()
