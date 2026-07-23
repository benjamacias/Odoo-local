using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace OdooNativeClient
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }

    internal sealed class OdooClient
    {
        private readonly JavaScriptSerializer serializer = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
        private readonly CookieContainer cookies = new CookieContainer();
        private string baseUrl;

        public OdooClient(string url)
        {
            baseUrl = (url ?? "").TrimEnd('/');
        }

        public string BaseUrl
        {
            get { return baseUrl; }
            set { baseUrl = (value ?? "").TrimEnd('/'); }
        }

        public Dictionary<string, object> Call(string path, Dictionary<string, object> parameters)
        {
            var envelope = new Dictionary<string, object>();
            envelope["jsonrpc"] = "2.0";
            envelope["method"] = "call";
            envelope["params"] = parameters ?? new Dictionary<string, object>();
            envelope["id"] = 1;

            var data = Encoding.UTF8.GetBytes(serializer.Serialize(envelope));
            var request = (HttpWebRequest)WebRequest.Create(baseUrl + path);
            request.Method = "POST";
            request.ContentType = "application/json";
            request.Accept = "application/json";
            request.CookieContainer = cookies;
            request.Timeout = 30000;
            request.ReadWriteTimeout = 30000;
            request.ContentLength = data.Length;

            using (var stream = request.GetRequestStream())
            {
                stream.Write(data, 0, data.Length);
            }

            using (var response = (HttpWebResponse)request.GetResponse())
            using (var stream = response.GetResponseStream())
            using (var reader = new StreamReader(stream, Encoding.UTF8))
            {
                var payload = reader.ReadToEnd();
                var root = serializer.DeserializeObject(payload) as Dictionary<string, object>;
                if (root == null)
                {
                    throw new InvalidOperationException("Respuesta JSON invalida.");
                }
                if (root.ContainsKey("error") && root["error"] != null)
                {
                    throw new InvalidOperationException(ExtractError(root["error"]));
                }
                return root.ContainsKey("result") ? AsDictionary(root["result"]) : new Dictionary<string, object>();
            }
        }

        private static string ExtractError(object error)
        {
            var dict = error as Dictionary<string, object>;
            if (dict == null) return Convert.ToString(error);
            if (dict.ContainsKey("data"))
            {
                var data = dict["data"] as Dictionary<string, object>;
                if (data != null && data.ContainsKey("message")) return Convert.ToString(data["message"]);
            }
            return dict.ContainsKey("message") ? Convert.ToString(dict["message"]) : "Odoo Server Error";
        }

        public static Dictionary<string, object> AsDictionary(object value)
        {
            var dict = value as Dictionary<string, object>;
            return dict ?? new Dictionary<string, object>();
        }

        public static IList AsList(object value)
        {
            var list = value as IList;
            return list ?? new ArrayList();
        }

        public static string Text(object value)
        {
            if (value == null || value is bool && !(bool)value) return "";
            var list = value as IList;
            if (list != null && list.Count > 1) return Convert.ToString(list[1]);
            return Convert.ToString(value);
        }

        public static int IntValue(object value)
        {
            if (value == null) return 0;
            if (value is int) return (int)value;
            int parsed;
            return int.TryParse(Convert.ToString(value), out parsed) ? parsed : 0;
        }
    }

    internal sealed class CacheEntry<T>
    {
        public T Value;
        public int Bytes;
        public DateTime CreatedAt;
        public string Model;
    }

    internal sealed class MemoryCache<T>
    {
        private readonly Dictionary<string, CacheEntry<T>> values = new Dictionary<string, CacheEntry<T>>();
        private readonly LinkedList<string> order = new LinkedList<string>();
        private readonly int maxBytes;
        private int currentBytes;

        public MemoryCache(int maxBytes)
        {
            this.maxBytes = maxBytes;
        }

        public bool TryGet(string key, string model, int ttlSeconds, out T value)
        {
            value = default(T);
            CacheEntry<T> entry;
            if (!values.TryGetValue(key, out entry)) return false;
            if ((DateTime.UtcNow - entry.CreatedAt).TotalSeconds > ttlSeconds)
            {
                Remove(key);
                return false;
            }
            Touch(key);
            value = entry.Value;
            return true;
        }

        public void Set(string key, string model, T value, int bytes)
        {
            if (bytes > maxBytes) return;
            Remove(key);
            values[key] = new CacheEntry<T> { Value = value, Bytes = bytes, CreatedAt = DateTime.UtcNow, Model = model };
            order.AddLast(key);
            currentBytes += bytes;
            Trim();
        }

        public void Clear()
        {
            values.Clear();
            order.Clear();
            currentBytes = 0;
        }

        public void ClearModel(string model)
        {
            var keys = values.Where(pair => pair.Value.Model == model).Select(pair => pair.Key).ToArray();
            foreach (var key in keys) Remove(key);
        }

        private void Touch(string key)
        {
            order.Remove(key);
            order.AddLast(key);
        }

        private void Trim()
        {
            while (currentBytes > maxBytes && order.Count > 0)
            {
                Remove(order.First.Value);
            }
        }

        private void Remove(string key)
        {
            CacheEntry<T> entry;
            if (!values.TryGetValue(key, out entry)) return;
            values.Remove(key);
            order.Remove(key);
            currentBytes = Math.Max(0, currentBytes - entry.Bytes);
        }
    }

    internal sealed class ViewState
    {
        public int Offset;
        public int SelectedId;
        public int FirstRow;
        public string Query = "";
        public string SearchField = "__all__";
    }

    internal sealed class MainForm : Form
    {
        private readonly Color background = Color.FromArgb(243, 246, 250);
        private readonly Color surface = Color.White;
        private readonly Color panel = Color.FromArgb(248, 250, 252);
        private readonly Color accent = Color.FromArgb(113, 75, 103);
        private readonly Color text = Color.FromArgb(23, 32, 51);
        private readonly Color subtle = Color.FromArgb(102, 112, 133);

        private OdooClient client;
        private TextBox urlBox;
        private TextBox dbBox;
        private TextBox loginBox;
        private TextBox passwordBox;
        private TextBox infoBox;
        private Label statusLabel;
        private Label moduleTitle;
        private Label moduleSubtitle;
        private Label detailTitle;
        private Label detailSubtitle;
        private TreeView appsTree;
        private TextBox navSearchBox;
        private ComboBox searchFieldBox;
        private TextBox searchBox;
        private DataGridView grid;
        private Panel detailBody;
        private SplitContainer mainSplit;
        private SplitContainer contentSplit;
        private Panel staticHost;
        private TableLayoutPanel loadingOverlay;
        private Label loadingTitle;
        private Label loadingSubtitle;
        private ProgressBar loadingProgress;
        private Button connectButton;
        private Button prevButton;
        private Button nextButton;
        private Button reloadButton;
        private Button searchButton;
        private Button newButton;
        private Button saveButton;
        private Label pageLabel;

        private Dictionary<string, object> snapshotRoot;
        private Dictionary<string, object> fields = new Dictionary<string, object>();
        private Dictionary<string, object> currentPermissions = new Dictionary<string, object>();
        private readonly Dictionary<string, Dictionary<string, object>> fieldCache = new Dictionary<string, Dictionary<string, object>>();
        private readonly Dictionary<string, Dictionary<string, object>> permissionsCache = new Dictionary<string, Dictionary<string, object>>();
        private readonly MemoryCache<Dictionary<string, object>> pageCache = new MemoryCache<Dictionary<string, object>>(2 * 1024 * 1024);
        private readonly MemoryCache<Dictionary<string, object>> detailCache = new MemoryCache<Dictionary<string, object>>(1024 * 1024);
        private readonly Dictionary<string, ViewState> viewStates = new Dictionary<string, ViewState>();

        private List<Dictionary<string, object>> records = new List<Dictionary<string, object>>();
        private Dictionary<string, object> currentRecord;
        private List<string> listFields = new List<string>();
        private List<string> detailFields = new List<string>();
        private string currentModel = "";
        private string currentTitle = "";
        private string currentViewKey = "";
        private ArrayList currentDomain = new ArrayList();
        private int offset;
        private const int Limit = 40;
        private int total;
        private bool suppressSelection;
        private bool suppressSearchReload;
        private bool readOnly;

        public MainForm()
        {
            Text = "Odoo Native Client";
            Width = 1440;
            Height = 820;
            MinimumSize = new Size(1080, 680);
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Segoe UI", 9);
            BackColor = background;

            BuildUi();
            ShowConnectionView();
        }

        private void BuildUi()
        {
            var root = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, ColumnCount = 1, BackColor = background };
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
            Controls.Add(root);

            var top = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 3, BackColor = surface, Padding = new Padding(12, 8, 12, 8) };
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 116));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 126));
            root.Controls.Add(top, 0, 0);

            infoBox = new TextBox { Dock = DockStyle.Fill, ReadOnly = true, BorderStyle = BorderStyle.None, Text = "Sin conectar | Conexion estatica y carga bajo demanda.", BackColor = Color.FromArgb(242, 234, 240), ForeColor = accent, Margin = new Padding(0, 2, 10, 0) };
            top.Controls.Add(infoBox, 0, 0);

            var connectionButton = FlatButton("Conexion", false);
            connectionButton.Click += delegate { ShowConnectionView(); };
            top.Controls.Add(connectionButton, 1, 0);

            connectButton = FlatButton("Conectar", true);
            connectButton.Click += async delegate { await ConnectAsync(); };
            top.Controls.Add(connectButton, 2, 0);

            mainSplit = new SplitContainer { Dock = DockStyle.Fill, FixedPanel = FixedPanel.Panel1, SplitterDistance = 300, Panel1MinSize = 260 };
            mainSplit.Panel1.BackColor = panel;
            mainSplit.Panel2.BackColor = background;
            root.Controls.Add(mainSplit, 0, 1);

            BuildNavigation();
            BuildContent();
            BuildStatus(root);
        }

        private void BuildNavigation()
        {
            var nav = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, ColumnCount = 1, BackColor = panel, Padding = new Padding(14, 12, 10, 10) };
            nav.RowStyles.Add(new RowStyle(SizeType.Absolute, 46));
            nav.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
            nav.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            mainSplit.Panel1.Controls.Add(nav);

            var title = new Label { Dock = DockStyle.Fill, Text = "Aplicaciones", Font = new Font("Segoe UI Semibold", 12), ForeColor = text, TextAlign = ContentAlignment.MiddleLeft };
            nav.Controls.Add(title, 0, 0);

            navSearchBox = InputBox("Buscar menu...");
            navSearchBox.TextChanged += delegate { RebuildAppsTree(navSearchBox.Text); };
            nav.Controls.Add(navSearchBox, 0, 1);

            appsTree = new TreeView { Dock = DockStyle.Fill, BorderStyle = BorderStyle.None, BackColor = panel, HideSelection = false, FullRowSelect = true, ShowLines = false, ShowPlusMinus = false, ItemHeight = 26, Font = new Font("Segoe UI", 9) };
            appsTree.AfterSelect += async delegate(object sender, TreeViewEventArgs args) { await OpenMenuAsync(args.Node.Tag as Dictionary<string, object>); };
            nav.Controls.Add(appsTree, 0, 2);
        }

        private void BuildContent()
        {
            contentSplit = new SplitContainer { Dock = DockStyle.Fill, FixedPanel = FixedPanel.Panel2, SplitterDistance = 760, Panel1MinSize = 520, Panel2MinSize = 320 };
            mainSplit.Panel2.Controls.Add(contentSplit);

            staticHost = new Panel { Dock = DockStyle.Fill, BackColor = background };
            mainSplit.Panel2.Controls.Add(staticHost);

            BuildConnectionView();
            BuildListView();
            BuildDetailView();
            BuildLoadingOverlay();
        }

        private void BuildConnectionView()
        {
            var view = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 4, ColumnCount = 1, BackColor = background, Padding = new Padding(28, 24, 28, 24) };
            view.RowStyles.Add(new RowStyle(SizeType.Absolute, 72));
            view.RowStyles.Add(new RowStyle(SizeType.Absolute, 184));
            view.RowStyles.Add(new RowStyle(SizeType.Absolute, 56));
            view.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            staticHost.Controls.Add(view);

            view.Controls.Add(new Label { Dock = DockStyle.Fill, Text = "Conexion", Font = new Font("Segoe UI Semibold", 18), ForeColor = text, TextAlign = ContentAlignment.BottomLeft }, 0, 0);

            var form = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 4, BackColor = background };
            form.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 130));
            form.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            for (var i = 0; i < 4; i++) form.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
            view.Controls.Add(form, 0, 1);

            urlBox = AddField(form, 0, "Servidor", "http://127.0.0.1:8069", false);
            dbBox = AddField(form, 1, "Base de datos", "odoo", false);
            loginBox = AddField(form, 2, "Usuario", "admin", false);
            passwordBox = AddField(form, 3, "Clave", "", true);

            var actions = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, BackColor = background };
            actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            actions.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 140));
            actions.Controls.Add(new Label { Dock = DockStyle.Fill, Text = "Arranque minimo: solo sesion y menus; los modelos se abren bajo demanda.", ForeColor = subtle, TextAlign = ContentAlignment.MiddleLeft }, 0, 0);
            var formConnect = FlatButton("Conectar", true);
            formConnect.Click += async delegate { await ConnectAsync(); };
            actions.Controls.Add(formConnect, 1, 0);
            view.Controls.Add(actions, 0, 2);

            view.Controls.Add(new Label { Dock = DockStyle.Top, AutoSize = true, Text = "Esta app compilada usa grilla virtual, cache por memoria, TTL por modelo, prefetch pequeno y detalle lazy para bajar consumo en PCs con poca RAM.", ForeColor = subtle }, 0, 3);
        }

        private void BuildListView()
        {
            var list = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 4, ColumnCount = 1, BackColor = background };
            list.RowStyles.Add(new RowStyle(SizeType.Absolute, 58));
            list.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
            list.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            list.RowStyles.Add(new RowStyle(SizeType.Absolute, 36));
            contentSplit.Panel1.Controls.Add(list);

            var header = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 2, ColumnCount = 1, Padding = new Padding(10, 8, 10, 0), BackColor = background };
            header.RowStyles.Add(new RowStyle(SizeType.Percent, 58));
            header.RowStyles.Add(new RowStyle(SizeType.Percent, 42));
            moduleTitle = new Label { Dock = DockStyle.Fill, Text = "Sin modelo", Font = new Font("Segoe UI Semibold", 14), ForeColor = text, TextAlign = ContentAlignment.BottomLeft };
            moduleSubtitle = new Label { Dock = DockStyle.Fill, Text = "Conecta y elegi una app", ForeColor = subtle, TextAlign = ContentAlignment.TopLeft };
            header.Controls.Add(moduleTitle, 0, 0);
            header.Controls.Add(moduleSubtitle, 0, 1);
            list.Controls.Add(header, 0, 0);

            var search = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 4, Padding = new Padding(10, 2, 10, 4), BackColor = background };
            search.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 160));
            search.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            search.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 92));
            search.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 92));
            searchFieldBox = new ComboBox { Dock = DockStyle.Fill, DropDownStyle = ComboBoxStyle.DropDownList, Margin = new Padding(0, 4, 8, 0) };
            searchFieldBox.SelectedIndexChanged += async delegate { if (!suppressSearchReload && searchBox.Text.Trim().Length > 0) await LoadPageAsync(0, 0, ""); };
            searchBox = InputBox("");
            searchBox.KeyDown += async delegate(object sender, KeyEventArgs args) { if (args.KeyCode == Keys.Enter) { args.SuppressKeyPress = true; await LoadPageAsync(0, 0, ""); } };
            searchButton = FlatButton("Buscar", false);
            searchButton.Click += async delegate { await LoadPageAsync(0, 0, ""); };
            reloadButton = FlatButton("Recargar", false);
            reloadButton.Click += async delegate { pageCache.ClearModel(currentModel); detailCache.ClearModel(currentModel); await LoadPageAsync(offset, 0, ""); };
            search.Controls.Add(searchFieldBox, 0, 0);
            search.Controls.Add(searchBox, 1, 0);
            search.Controls.Add(searchButton, 2, 0);
            search.Controls.Add(reloadButton, 3, 0);
            list.Controls.Add(search, 0, 1);

            grid = new DataGridView { Dock = DockStyle.Fill, ReadOnly = true, RowHeadersVisible = false, SelectionMode = DataGridViewSelectionMode.FullRowSelect, MultiSelect = false, VirtualMode = true, AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill, AllowUserToAddRows = false, AllowUserToDeleteRows = false, Margin = new Padding(10, 2, 10, 0) };
            StyleGrid(grid);
            grid.CellValueNeeded += GridCellValueNeeded;
            grid.SelectionChanged += async delegate { if (!suppressSelection) await LoadSelectedDetailAsync(); };
            list.Controls.Add(grid, 0, 2);

            var pager = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 4, Padding = new Padding(10, 4, 10, 4), BackColor = background };
            pager.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 90));
            pager.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 90));
            pager.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            pager.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 104));
            prevButton = FlatButton("Anterior", false);
            prevButton.Click += async delegate { await LoadPageAsync(offset - Limit, 0, ""); };
            nextButton = FlatButton("Siguiente", false);
            nextButton.Click += async delegate { await LoadPageAsync(offset + Limit, 0, ""); };
            pageLabel = new Label { Dock = DockStyle.Fill, Text = "0-0 de 0", TextAlign = ContentAlignment.MiddleCenter, Font = new Font("Segoe UI", 9, FontStyle.Bold), ForeColor = text };
            newButton = FlatButton("Nuevo", false);
            newButton.Click += async delegate { await CreateRecordAsync(); };
            pager.Controls.Add(prevButton, 0, 0);
            pager.Controls.Add(nextButton, 1, 0);
            pager.Controls.Add(pageLabel, 2, 0);
            pager.Controls.Add(newButton, 3, 0);
            list.Controls.Add(pager, 0, 3);
        }

        private void BuildDetailView()
        {
            var detail = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, ColumnCount = 1, Padding = new Padding(14, 12, 14, 12), BackColor = surface };
            detail.RowStyles.Add(new RowStyle(SizeType.Absolute, 64));
            detail.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            detail.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
            contentSplit.Panel2.Controls.Add(detail);

            var header = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 2, ColumnCount = 1, BackColor = surface };
            header.RowStyles.Add(new RowStyle(SizeType.Percent, 62));
            header.RowStyles.Add(new RowStyle(SizeType.Percent, 38));
            detailTitle = new Label { Dock = DockStyle.Fill, Text = "Detalle", Font = new Font("Segoe UI Semibold", 13), ForeColor = text, TextAlign = ContentAlignment.BottomLeft };
            detailSubtitle = new Label { Dock = DockStyle.Fill, Text = "", ForeColor = subtle, TextAlign = ContentAlignment.TopLeft };
            header.Controls.Add(detailTitle, 0, 0);
            header.Controls.Add(detailSubtitle, 0, 1);
            detail.Controls.Add(header, 0, 0);

            detailBody = new Panel { Dock = DockStyle.Fill, AutoScroll = true, BackColor = surface };
            detail.Controls.Add(detailBody, 0, 1);

            saveButton = FlatButton("Guardar", true);
            saveButton.Click += async delegate { await SaveRecordAsync(); };
            detail.Controls.Add(saveButton, 0, 2);
        }

        private void BuildLoadingOverlay()
        {
            loadingOverlay = new TableLayoutPanel { Dock = DockStyle.Fill, BackColor = panel, ColumnCount = 3, RowCount = 5, Visible = false, Padding = new Padding(28, 24, 28, 24) };
            loadingOverlay.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
            loadingOverlay.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 520));
            loadingOverlay.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
            loadingOverlay.RowStyles.Add(new RowStyle(SizeType.Percent, 50));
            loadingOverlay.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
            loadingOverlay.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
            loadingOverlay.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
            loadingOverlay.RowStyles.Add(new RowStyle(SizeType.Percent, 50));
            mainSplit.Panel2.Controls.Add(loadingOverlay);

            loadingTitle = new Label { Dock = DockStyle.Fill, Text = "Cargando", Font = new Font("Segoe UI Semibold", 16), ForeColor = text, TextAlign = ContentAlignment.BottomCenter };
            loadingSubtitle = new Label { Dock = DockStyle.Fill, Text = "Preparando vista nativa", ForeColor = subtle, TextAlign = ContentAlignment.MiddleCenter };
            loadingProgress = new ProgressBar { Dock = DockStyle.Fill, Style = ProgressBarStyle.Marquee, MarqueeAnimationSpeed = 0, Margin = new Padding(62, 6, 62, 6) };
            loadingOverlay.Controls.Add(loadingTitle, 1, 1);
            loadingOverlay.Controls.Add(loadingSubtitle, 1, 2);
            loadingOverlay.Controls.Add(loadingProgress, 1, 3);
        }

        private void BuildStatus(TableLayoutPanel root)
        {
            statusLabel = new Label { Dock = DockStyle.Fill, Text = "Listo.", TextAlign = ContentAlignment.MiddleLeft, Padding = new Padding(10, 0, 0, 0), ForeColor = subtle, BackColor = background };
            root.Controls.Add(statusLabel, 0, 2);
        }

        private TextBox AddField(TableLayoutPanel form, int row, string label, string value, bool password)
        {
            form.Controls.Add(new Label { Dock = DockStyle.Fill, Text = label, ForeColor = subtle, TextAlign = ContentAlignment.MiddleLeft }, 0, row);
            var box = new TextBox { Dock = DockStyle.Fill, Text = value, UseSystemPasswordChar = password, Margin = new Padding(0, 6, 0, 6), BorderStyle = BorderStyle.FixedSingle };
            form.Controls.Add(box, 1, row);
            return box;
        }

        private TextBox InputBox(string placeholder)
        {
            return new TextBox { Dock = DockStyle.Fill, Margin = new Padding(0, 4, 8, 0), BorderStyle = BorderStyle.FixedSingle };
        }

        private Button FlatButton(string caption, bool primary)
        {
            var button = new Button { Dock = DockStyle.Fill, Text = caption, FlatStyle = FlatStyle.Flat, Cursor = Cursors.Hand, BackColor = primary ? accent : surface, ForeColor = primary ? Color.White : text, Margin = new Padding(0, 0, 8, 0) };
            button.FlatAppearance.BorderColor = primary ? accent : Color.FromArgb(214, 222, 233);
            return button;
        }

        private void StyleGrid(DataGridView target)
        {
            target.BackgroundColor = surface;
            target.BorderStyle = BorderStyle.None;
            target.CellBorderStyle = DataGridViewCellBorderStyle.SingleHorizontal;
            target.GridColor = Color.FromArgb(233, 238, 245);
            target.EnableHeadersVisualStyles = false;
            target.ColumnHeadersDefaultCellStyle.BackColor = Color.FromArgb(238, 242, 247);
            target.ColumnHeadersDefaultCellStyle.ForeColor = text;
            target.ColumnHeadersDefaultCellStyle.Font = new Font("Segoe UI", 9, FontStyle.Bold);
            target.ColumnHeadersHeight = 36;
            target.RowTemplate.Height = 32;
            target.DefaultCellStyle.Font = new Font("Segoe UI", 9);
            target.DefaultCellStyle.SelectionBackColor = Color.FromArgb(37, 99, 235);
            target.DefaultCellStyle.SelectionForeColor = Color.White;
            target.AlternatingRowsDefaultCellStyle.BackColor = Color.FromArgb(250, 251, 253);
        }

        private async Task ConnectAsync()
        {
            await RunBusy("Conectando con Odoo", "Validando bridge, usuario y menus.", delegate
            {
                client = new OdooClient(urlBox.Text);
                pageCache.Clear();
                detailCache.Clear();
                viewStates.Clear();
                currentViewKey = "";

                var health = client.Call("/native-ui/health", null);
                client.Call("/web/session/authenticate", new Dictionary<string, object> { { "db", dbBox.Text }, { "login", loginBox.Text }, { "password", passwordBox.Text } });
                var session = client.Call("/native-ui/session", null);
                var snapshot = client.Call("/native-ui/snapshot/index", null);
                snapshotRoot = OdooClient.AsDictionary(snapshot.ContainsKey("menus") ? snapshot["menus"] : null);

                BeginInvoke((Action)delegate
                {
                    RebuildAppsTree("");
                    connectButton.Text = "Reconectar";
                    infoBox.Text = "Conectado | Odoo " + OdooClient.Text(health.ContainsKey("odoo_version") ? health["odoo_version"] : "") + " | " + OdooClient.Text(session.ContainsKey("database") ? session["database"] : "") + " | Bridge " + OdooClient.Text(health.ContainsKey("bridge_version") ? health["bridge_version"] : "");
                    ShowConnectionView();
                    SetStatus("Conectado. Elegi una app para cargarla bajo demanda.");
                });
            });
        }

        private void RebuildAppsTree(string filter)
        {
            appsTree.BeginUpdate();
            try
            {
                appsTree.Nodes.Clear();
                var connectionNode = new TreeNode("Conexion") { Tag = new Dictionary<string, object> { { "static_view", "connection" }, { "name", "Conexion" } } };
                appsTree.Nodes.Add(connectionNode);
                if (snapshotRoot == null) return;
                var children = OdooClient.AsList(snapshotRoot.ContainsKey("children") ? snapshotRoot["children"] : null);
                foreach (var item in children)
                {
                    var menu = OdooClient.AsDictionary(item);
                    var node = BuildMenuNode(menu, (filter ?? "").Trim().ToLowerInvariant());
                    if (node != null) appsTree.Nodes.Add(node);
                }
                if (!string.IsNullOrWhiteSpace(filter)) appsTree.ExpandAll();
            }
            finally
            {
                appsTree.EndUpdate();
            }
        }

        private TreeNode BuildMenuNode(Dictionary<string, object> menu, string filter)
        {
            var name = OdooClient.Text(menu.ContainsKey("name") ? menu["name"] : "");
            var matches = string.IsNullOrEmpty(filter) || name.ToLowerInvariant().Contains(filter);
            var node = new TreeNode(name) { Tag = menu };
            foreach (var child in OdooClient.AsList(menu.ContainsKey("children") ? menu["children"] : null))
            {
                var childNode = BuildMenuNode(OdooClient.AsDictionary(child), filter);
                if (childNode != null)
                {
                    matches = true;
                    node.Nodes.Add(childNode);
                }
            }
            return matches ? node : null;
        }

        private async Task OpenMenuAsync(Dictionary<string, object> menu)
        {
            if (menu == null) return;
            if (menu.ContainsKey("static_view"))
            {
                SaveCurrentViewState();
                ShowConnectionView();
                return;
            }
            var actionMenu = FindFirstActionMenu(menu);
            if (actionMenu == null)
            {
                SetStatus("Menu sin accion directa.");
                return;
            }
            await RunBusy("Abriendo " + OdooClient.Text(actionMenu["name"]), "Resolviendo accion y metadata.", delegate
            {
                var actionRef = OdooClient.AsDictionary(actionMenu.ContainsKey("action") ? actionMenu["action"] : null);
                var parameters = new Dictionary<string, object>();
                if (actionRef.ContainsKey("raw")) parameters["action_ref"] = OdooClient.Text(actionRef["raw"]);
                else if (actionRef.ContainsKey("id")) parameters["action_id"] = OdooClient.IntValue(actionRef["id"]);
                var action = client.Call("/native-ui/action", parameters);
                if (!action.ContainsKey("res_model"))
                {
                    BeginInvoke((Action)delegate { SetStatus("Accion no representable todavia."); });
                    return;
                }
                var model = OdooClient.Text(action["res_model"]);
                var title = OdooClient.Text(actionMenu["name"]);
                var domain = OdooClient.AsList(action.ContainsKey("domain_native") ? action["domain_native"] : null);
                BeginInvoke((Action)(async delegate { await LoadModelAsync(model, title, domain); }));
            });
        }

        private Dictionary<string, object> FindFirstActionMenu(Dictionary<string, object> menu)
        {
            if (HasUsableAction(menu)) return menu;
            foreach (var child in OdooClient.AsList(menu.ContainsKey("children") ? menu["children"] : null))
            {
                var found = FindFirstActionMenu(OdooClient.AsDictionary(child));
                if (found != null) return found;
            }
            return null;
        }

        private bool HasUsableAction(Dictionary<string, object> menu)
        {
            if (!menu.ContainsKey("action") || menu["action"] == null) return false;
            var action = OdooClient.AsDictionary(menu["action"]);
            return action.ContainsKey("id") || action.ContainsKey("raw");
        }

        private async Task LoadModelAsync(string model, string title, IList domain)
        {
            SaveCurrentViewState();
            currentModel = model;
            currentTitle = title;
            currentDomain = new ArrayList(domain);
            currentViewKey = model + "|" + title + "|" + JsonKey(currentDomain);
            ViewState state;
            viewStates.TryGetValue(currentViewKey, out state);

            contentSplit.Visible = true;
            staticHost.Visible = false;
            contentSplit.BringToFront();
            Text = "Odoo Native Client - " + title;
            moduleTitle.Text = title;
            moduleSubtitle.Text = model;

            await RunBusy("Preparando " + title, "Cargando metadata compacta y permisos.", delegate
            {
                if (!fieldCache.TryGetValue(model, out fields))
                {
                    var result = client.Call("/native-ui/model/" + model + "/fields", new Dictionary<string, object> { { "attributes", new object[] { "string", "type", "readonly", "required", "relation", "selection", "store" } } });
                    fields = OdooClient.AsDictionary(result.ContainsKey("fields") ? result["fields"] : null);
                    fieldCache[model] = fields;
                }
                if (!permissionsCache.TryGetValue(model, out currentPermissions))
                {
                    var permissions = client.Call("/native-ui/model/" + model + "/permissions", null);
                    currentPermissions = OdooClient.AsDictionary(permissions.ContainsKey("permissions") ? permissions["permissions"] : null);
                    permissionsCache[model] = currentPermissions;
                }
                listFields = PreferredListFields();
                detailFields = PreferredDetailFields();
                BeginInvoke((Action)delegate
                {
                    UpdateSearchFields(state);
                    readOnly = !BoolPermission("write");
                    newButton.Enabled = BoolPermission("create");
                    saveButton.Enabled = !readOnly;
                });
            });

            await LoadPageAsync(state != null ? state.Offset : 0, state != null ? state.SelectedId : 0, "");
            if (state != null) RestoreScroll(state);
        }

        private async Task LoadPageAsync(int requestedOffset, int selectId, string order)
        {
            if (client == null || string.IsNullOrEmpty(currentModel)) return;
            offset = Math.Max(0, requestedOffset);
            SaveCurrentViewState();
            await RunBusy("Cargando " + currentTitle, "Usando cache si la vista ya fue visitada.", delegate
            {
                var queryDomain = BuildSearchDomain();
                var readFields = new ArrayList();
                readFields.Add("display_name");
                foreach (var field in listFields) if (!readFields.Contains(field)) readFields.Add(field);
                var resolvedOrder = string.IsNullOrEmpty(order) ? (HasField("name") ? "name" : "id") : order;
                var key = PageKey(queryDomain, readFields, offset, resolvedOrder);
                Dictionary<string, object> page;
                var usedCache = pageCache.TryGet(key, currentModel, ModelTtl(currentModel), out page);
                if (!usedCache)
                {
                    page = client.Call("/native-ui/model/" + currentModel + "/records", new Dictionary<string, object>
                    {
                        { "domain", queryDomain },
                        { "fields", readFields },
                        { "offset", offset },
                        { "limit", Limit },
                        { "count", true },
                        { "order", resolvedOrder }
                    });
                    pageCache.Set(key, currentModel, page, ApproxBytes(page));
                }

                var newRecords = new List<Dictionary<string, object>>();
                foreach (var item in OdooClient.AsList(page.ContainsKey("records") ? page["records"] : null))
                {
                    newRecords.Add(OdooClient.AsDictionary(item));
                }
                var newTotal = OdooClient.IntValue(page.ContainsKey("total") ? page["total"] : newRecords.Count);

                BeginInvoke((Action)delegate
                {
                    records = newRecords;
                    total = newTotal;
                    RenderPage(selectId, usedCache);
                });

                if (!usedCache) PrefetchNextPage(queryDomain, readFields, resolvedOrder);
            });
        }

        private void RenderPage(int selectId, bool usedCache)
        {
            EnsureGridColumns();
            suppressSelection = true;
            grid.RowCount = 0;
            grid.RowCount = records.Count;
            suppressSelection = false;

            var start = total == 0 ? 0 : offset + 1;
            var end = Math.Min(offset + records.Count, total);
            pageLabel.Text = start + "-" + end + " de " + total;
            moduleSubtitle.Text = currentModel + " | " + pageLabel.Text + (usedCache ? " | cache" : "");
            prevButton.Enabled = offset > 0;
            nextButton.Enabled = offset + Limit < total;

            if (records.Count == 0)
            {
                ShowEmptyDetail();
                return;
            }

            var selectedIndex = 0;
            if (selectId > 0)
            {
                for (var i = 0; i < records.Count; i++)
                {
                    if (OdooClient.IntValue(records[i].ContainsKey("id") ? records[i]["id"] : null) == selectId)
                    {
                        selectedIndex = i;
                        break;
                    }
                }
            }
            grid.ClearSelection();
            grid.Rows[selectedIndex].Selected = true;
            grid.CurrentCell = grid.Rows[selectedIndex].Cells[0];
            var ignored = LoadSelectedDetailAsync();
        }

        private async Task LoadSelectedDetailAsync()
        {
            if (grid.SelectedRows.Count == 0) return;
            var index = grid.SelectedRows[0].Index;
            if (index < 0 || index >= records.Count) return;
            var listRecord = records[index];
            var id = OdooClient.IntValue(listRecord.ContainsKey("id") ? listRecord["id"] : null);
            var detailFieldsToRead = new ArrayList();
            detailFieldsToRead.Add("display_name");
            foreach (var field in listFields) if (!detailFieldsToRead.Contains(field)) detailFieldsToRead.Add(field);
            foreach (var field in detailFields) if (!detailFieldsToRead.Contains(field)) detailFieldsToRead.Add(field);
            var key = currentModel + "|" + id + "|" + JsonKey(detailFieldsToRead);
            Dictionary<string, object> detail;
            if (!detailCache.TryGet(key, currentModel, ModelTtl(currentModel), out detail))
            {
                await RunBusy("Cargando detalle", "Leyendo registro seleccionado bajo demanda.", delegate
                {
                    var result = client.Call("/native-ui/model/" + currentModel + "/record/" + id, new Dictionary<string, object> { { "fields", detailFieldsToRead } });
                    detail = OdooClient.AsDictionary(result.ContainsKey("record") ? result["record"] : null);
                    detailCache.Set(key, currentModel, detail, ApproxBytes(detail));
                });
            }
            currentRecord = detail;
            RenderDetail(detail);
        }

        private void RenderDetail(Dictionary<string, object> record)
        {
            detailBody.Controls.Clear();
            if (record == null || record.Count == 0)
            {
                ShowEmptyDetail();
                return;
            }
            detailTitle.Text = OdooClient.Text(record.ContainsKey("display_name") ? record["display_name"] : "");
            detailSubtitle.Text = currentModel + " | ID " + OdooClient.Text(record.ContainsKey("id") ? record["id"] : "");
            var table = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 2, BackColor = surface, Padding = new Padding(0, 2, 0, 10) };
            table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 140));
            table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            foreach (var field in detailFields)
            {
                AddDetailRow(table, field, record.ContainsKey(field) ? record[field] : null);
            }
            detailBody.Controls.Add(table);
        }

        private void AddDetailRow(TableLayoutPanel table, string field, object value)
        {
            var row = table.RowCount++;
            table.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            table.Controls.Add(new Label { Text = FieldTitle(field), AutoSize = true, Margin = new Padding(0, 8, 10, 4), ForeColor = text }, 0, row);
            table.Controls.Add(new TextBox { Text = OdooClient.Text(value), ReadOnly = readOnly || !IsEditable(field), Dock = DockStyle.Fill, Margin = new Padding(0, 4, 0, 4), BorderStyle = BorderStyle.FixedSingle, Tag = field }, 1, row);
        }

        private async Task SaveRecordAsync()
        {
            if (readOnly || currentRecord == null) return;
            var id = OdooClient.IntValue(currentRecord.ContainsKey("id") ? currentRecord["id"] : null);
            var values = new Dictionary<string, object>();
            foreach (Control control in detailBody.Controls)
            {
                CollectValues(control, values);
            }
            if (values.Count == 0) return;
            await RunBusy("Guardando registro", "Invalidando cache del modelo.", delegate
            {
                client.Call("/native-ui/model/" + currentModel + "/write", new Dictionary<string, object> { { "ids", new object[] { id } }, { "values", values } });
                pageCache.ClearModel(currentModel);
                detailCache.ClearModel(currentModel);
            });
            await LoadPageAsync(offset, id, "");
        }

        private async Task CreateRecordAsync()
        {
            if (!HasField("name")) return;
            await RunBusy("Creando registro", "Creacion minima y seleccion automatica.", delegate
            {
                var result = client.Call("/native-ui/model/" + currentModel + "/create", new Dictionary<string, object> { { "values", new Dictionary<string, object> { { "name", "Nuevo registro" } } } });
                pageCache.ClearModel(currentModel);
                detailCache.ClearModel(currentModel);
                var id = OdooClient.IntValue(result.ContainsKey("id") ? result["id"] : null);
                BeginInvoke((Action)(async delegate { searchBox.Text = ""; await LoadPageAsync(0, id, "id desc"); }));
            });
        }

        private void CollectValues(Control control, Dictionary<string, object> values)
        {
            var box = control as TextBox;
            if (box != null && box.Tag is string && !box.ReadOnly)
            {
                values[(string)box.Tag] = box.Text;
            }
            foreach (Control child in control.Controls) CollectValues(child, values);
        }

        private void ShowEmptyDetail()
        {
            currentRecord = null;
            detailBody.Controls.Clear();
            detailTitle.Text = "Sin registro";
            detailSubtitle.Text = "";
        }

        private void EnsureGridColumns()
        {
            var signature = "id|" + string.Join("|", listFields.ToArray());
            if (grid.Tag as string == signature && grid.Columns.Count > 0) return;
            grid.RowCount = 0;
            grid.Columns.Clear();
            grid.Columns.Add("id", "ID");
            grid.Columns["id"].FillWeight = 12;
            foreach (var field in listFields)
            {
                grid.Columns.Add(field, FieldTitle(field));
                grid.Columns[field].FillWeight = field == "display_name" || field == "name" ? 42 : 24;
            }
            grid.Tag = signature;
        }

        private void GridCellValueNeeded(object sender, DataGridViewCellValueEventArgs args)
        {
            if (args.RowIndex < 0 || args.RowIndex >= records.Count) return;
            if (args.ColumnIndex < 0 || args.ColumnIndex >= grid.Columns.Count) return;
            var field = grid.Columns[args.ColumnIndex].Name;
            var record = records[args.RowIndex];
            args.Value = OdooClient.Text(record.ContainsKey(field) ? record[field] : null);
        }

        private ArrayList BuildSearchDomain()
        {
            var domain = new ArrayList(currentDomain);
            var query = searchBox.Text.Trim();
            if (query.Length == 0) return domain;
            var selected = searchFieldBox.SelectedValue == null ? "__all__" : Convert.ToString(searchFieldBox.SelectedValue);
            if (selected != "__all__" && IsSearchable(selected))
            {
                domain.Add(new object[] { selected, "ilike", query });
                return domain;
            }
            var fieldsToSearch = new List<string> { "display_name" };
            fieldsToSearch.AddRange(listFields.Where(IsSearchable).Take(4));
            fieldsToSearch = fieldsToSearch.Distinct().Take(5).ToList();
            for (var i = 0; i < fieldsToSearch.Count - 1; i++) domain.Add("|");
            foreach (var field in fieldsToSearch) domain.Add(new object[] { field, "ilike", query });
            return domain;
        }

        private void PrefetchNextPage(ArrayList domain, ArrayList readFields, string order)
        {
            if (offset + Limit >= total) return;
            ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    var nextOffset = offset + Limit;
                    var key = PageKey(domain, readFields, nextOffset, order);
                    Dictionary<string, object> ignored;
                    if (pageCache.TryGet(key, currentModel, ModelTtl(currentModel), out ignored)) return;
                    var result = client.Call("/native-ui/model/" + currentModel + "/records", new Dictionary<string, object>
                    {
                        { "domain", domain },
                        { "fields", readFields },
                        { "offset", nextOffset },
                        { "limit", Limit },
                        { "count", false },
                        { "order", order }
                    });
                    result["total"] = total;
                    pageCache.Set(key, currentModel, result, ApproxBytes(result));
                }
                catch
                {
                }
            });
        }

        private void UpdateSearchFields(ViewState state)
        {
            suppressSearchReload = true;
            try
            {
                searchFieldBox.DataSource = null;
                var options = new List<KeyValuePair<string, string>>();
                options.Add(new KeyValuePair<string, string>("__all__", "Todo visible"));
                foreach (var field in (new[] { "display_name" }).Concat(listFields).Concat(detailFields).Distinct())
                {
                    if (IsSearchable(field)) options.Add(new KeyValuePair<string, string>(field, FieldTitle(field)));
                }
                searchFieldBox.DisplayMember = "Value";
                searchFieldBox.ValueMember = "Key";
                searchFieldBox.DataSource = options;
                searchBox.Text = state == null ? "" : state.Query;
                searchFieldBox.SelectedValue = state == null ? "__all__" : state.SearchField;
            }
            finally
            {
                suppressSearchReload = false;
            }
        }

        private void SaveCurrentViewState()
        {
            if (string.IsNullOrEmpty(currentViewKey)) return;
            var state = new ViewState();
            state.Offset = offset;
            state.Query = searchBox == null ? "" : searchBox.Text;
            state.SearchField = searchFieldBox == null || searchFieldBox.SelectedValue == null ? "__all__" : Convert.ToString(searchFieldBox.SelectedValue);
            state.SelectedId = currentRecord == null ? 0 : OdooClient.IntValue(currentRecord.ContainsKey("id") ? currentRecord["id"] : null);
            try { state.FirstRow = grid.RowCount > 0 ? grid.FirstDisplayedScrollingRowIndex : 0; } catch { state.FirstRow = 0; }
            viewStates[currentViewKey] = state;
        }

        private void RestoreScroll(ViewState state)
        {
            if (state == null || grid.RowCount == 0) return;
            try { grid.FirstDisplayedScrollingRowIndex = Math.Min(Math.Max(0, state.FirstRow), grid.RowCount - 1); } catch { }
        }

        private void ShowConnectionView()
        {
            SaveCurrentViewState();
            staticHost.Visible = true;
            contentSplit.Visible = false;
            staticHost.BringToFront();
            Text = "Odoo Native Client - Conexion";
            SetStatus("Vista estatica de conexion.");
        }

        private async Task RunBusy(string title, string subtitle, Action action)
        {
            ShowBusy(title, subtitle);
            try
            {
                await Task.Factory.StartNew(action);
            }
            catch (Exception ex)
            {
                if (InvokeRequired)
                {
                    BeginInvoke((Action)(delegate { ShowError(ex); }));
                }
                else
                {
                    ShowError(ex);
                }
            }
            finally
            {
                HideBusy();
            }
        }

        private void ShowError(Exception ex)
        {
            SetStatus("Error: " + ex.Message);
            MessageBox.Show(this, ex.Message, "Odoo Native Client", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }

        private void ShowBusy(string title, string subtitle)
        {
            loadingTitle.Text = title;
            loadingSubtitle.Text = subtitle;
            loadingProgress.MarqueeAnimationSpeed = 28;
            loadingOverlay.Visible = true;
            loadingOverlay.BringToFront();
            Cursor = Cursors.WaitCursor;
            SetStatus(title);
        }

        private void HideBusy()
        {
            if (InvokeRequired)
            {
                BeginInvoke((Action)HideBusy);
                return;
            }
            loadingProgress.MarqueeAnimationSpeed = 0;
            loadingOverlay.Visible = false;
            Cursor = Cursors.Default;
        }

        private void SetStatus(string value)
        {
            statusLabel.Text = value;
        }

        private List<string> PreferredListFields()
        {
            return new[] { "display_name", "name", "email", "phone", "mobile", "default_code", "list_price", "qty_available" }.Where(HasField).Distinct().Take(6).ToList();
        }

        private List<string> PreferredDetailFields()
        {
            return new[] { "name", "email", "phone", "mobile", "company_id", "street", "city", "country_id", "vat", "website", "default_code", "list_price", "qty_available" }.Where(HasField).Distinct().Take(14).ToList();
        }

        private bool HasField(string field)
        {
            return field == "display_name" || fields.ContainsKey(field);
        }

        private string FieldTitle(string field)
        {
            if (field == "display_name") return "Nombre";
            var meta = fields.ContainsKey(field) ? fields[field] as Dictionary<string, object> : null;
            return meta != null && meta.ContainsKey("string") ? OdooClient.Text(meta["string"]) : field;
        }

        private bool IsSearchable(string field)
        {
            if (field == "display_name") return true;
            var meta = fields.ContainsKey(field) ? fields[field] as Dictionary<string, object> : null;
            if (meta == null || !meta.ContainsKey("type")) return false;
            var type = OdooClient.Text(meta["type"]);
            return type == "char" || type == "text" || type == "html" || type == "phone" || type == "url" || type == "email" || type == "many2one" || type == "selection";
        }

        private bool IsEditable(string field)
        {
            var meta = fields.ContainsKey(field) ? fields[field] as Dictionary<string, object> : null;
            if (meta == null) return false;
            var type = meta.ContainsKey("type") ? OdooClient.Text(meta["type"]) : "";
            var readonlyValue = meta.ContainsKey("readonly") && meta["readonly"] is bool && (bool)meta["readonly"];
            return !readonlyValue && (type == "char" || type == "text" || type == "html" || type == "phone" || type == "url" || type == "email" || type == "selection");
        }

        private bool BoolPermission(string name)
        {
            return currentPermissions.ContainsKey(name) && currentPermissions[name] is bool && (bool)currentPermissions[name];
        }

        private static int ModelTtl(string model)
        {
            if (model.StartsWith("mail.") || model.StartsWith("discuss.")) return 20;
            if (model.StartsWith("stock.")) return 45;
            return 180;
        }

        private string PageKey(ArrayList domain, ArrayList fieldsToRead, int pageOffset, string order)
        {
            return currentModel + "|" + pageOffset + "|" + Limit + "|" + order + "|" + JsonKey(domain) + "|" + JsonKey(fieldsToRead);
        }

        private string JsonKey(object value)
        {
            return new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Serialize(value);
        }

        private int ApproxBytes(object value)
        {
            return Encoding.UTF8.GetByteCount(JsonKey(value));
        }
    }
}
