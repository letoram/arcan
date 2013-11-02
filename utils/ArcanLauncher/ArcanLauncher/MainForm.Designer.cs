namespace ArcanLauncher
{
    partial class LauncherForm
    {
        /// <summary>
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary>
        /// Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(LauncherForm));
            this.MainTab = new System.Windows.Forms.TabControl();
            this.ArcanTP = new System.Windows.Forms.TabPage();
            this.BASEBTN = new System.Windows.Forms.Button();
            this.BasedirTB = new System.Windows.Forms.TextBox();
            this.label7 = new System.Windows.Forms.Label();
            this.PrewakeSelector = new System.Windows.Forms.NumericUpDown();
            this.ThemePathTB = new System.Windows.Forms.TextBox();
            this.ResourcePathTB = new System.Windows.Forms.TextBox();
            this.DatabaseTB = new System.Windows.Forms.TextBox();
            this.ySelector = new System.Windows.Forms.NumericUpDown();
            this.xSelector = new System.Windows.Forms.NumericUpDown();
            this.label8 = new System.Windows.Forms.Label();
            this.HeightSelector = new System.Windows.Forms.NumericUpDown();
            this.label6 = new System.Windows.Forms.Label();
            this.WidthSelector = new System.Windows.Forms.NumericUpDown();
            this.label5 = new System.Windows.Forms.Label();
            this.LaunchArcanBTN = new System.Windows.Forms.Button();
            this.CMDLine = new System.Windows.Forms.TextBox();
            this.SilentCB = new System.Windows.Forms.CheckBox();
            this.ConservativeCB = new System.Windows.Forms.CheckBox();
            this.WaitSleepCB = new System.Windows.Forms.CheckBox();
            this.VSYNCCB = new System.Windows.Forms.CheckBox();
            this.DBBTN = new System.Windows.Forms.Button();
            this.label1 = new System.Windows.Forms.Label();
            this.TPathBTN = new System.Windows.Forms.Button();
            this.RPathBTN = new System.Windows.Forms.Button();
            this.ThemeList = new System.Windows.Forms.ListBox();
            this.NoBorderCB = new System.Windows.Forms.CheckBox();
            this.FullscreenCB = new System.Windows.Forms.CheckBox();
            this.DatabaseTP = new System.Windows.Forms.TabPage();
            this.DBTgtDbBTN = new System.Windows.Forms.Button();
            this.tabControl1 = new System.Windows.Forms.TabControl();
            this.tabPage1 = new System.Windows.Forms.TabPage();
            this.TargetsLB = new System.Windows.Forms.ListBox();
            this.skipRB = new System.Windows.Forms.RadioButton();
            this.scanRB = new System.Windows.Forms.RadioButton();
            this.UpdateOnlyCB = new System.Windows.Forms.CheckBox();
            this.DisableGenericCB = new System.Windows.Forms.CheckBox();
            this.tabPage3 = new System.Windows.Forms.TabPage();
            this.ScrapeMetaMedia = new System.Windows.Forms.CheckBox();
            this.ScrapeMeta = new System.Windows.Forms.CheckBox();
            this.NoStripCB = new System.Windows.Forms.CheckBox();
            this.tabPage4 = new System.Windows.Forms.TabPage();
            this.MameGoodCB = new System.Windows.Forms.CheckBox();
            this.ShortenTitlesCB = new System.Windows.Forms.CheckBox();
            this.MameSkipCloneCB = new System.Windows.Forms.CheckBox();
            this.forceVerifyCB = new System.Windows.Forms.CheckBox();
            this.tabPage5 = new System.Windows.Forms.TabPage();
            this.ShortenTitles = new System.Windows.Forms.CheckBox();
            this.FBSkipClonesCB = new System.Windows.Forms.CheckBox();
            this.label4 = new System.Windows.Forms.Label();
            this.DbResBTN = new System.Windows.Forms.Button();
            this.resPathTB = new System.Windows.Forms.TextBox();
            this.BuildBTN = new System.Windows.Forms.Button();
            this.label3 = new System.Windows.Forms.Label();
            this.TargetDatabaseTB = new System.Windows.Forms.TextBox();
            this.OutputTP = new System.Windows.Forms.TabPage();
            this.OutputErrLB = new System.Windows.Forms.ListBox();
            this.outputLB = new System.Windows.Forms.ListBox();
            this.folderSelector = new System.Windows.Forms.FolderBrowserDialog();
            this.dbSelector = new System.Windows.Forms.OpenFileDialog();
            this.newdbSelector = new System.Windows.Forms.OpenFileDialog();
            this.MainTab.SuspendLayout();
            this.ArcanTP.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.PrewakeSelector)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.ySelector)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.xSelector)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.HeightSelector)).BeginInit();
            ((System.ComponentModel.ISupportInitialize)(this.WidthSelector)).BeginInit();
            this.DatabaseTP.SuspendLayout();
            this.tabControl1.SuspendLayout();
            this.tabPage1.SuspendLayout();
            this.tabPage3.SuspendLayout();
            this.tabPage4.SuspendLayout();
            this.tabPage5.SuspendLayout();
            this.OutputTP.SuspendLayout();
            this.SuspendLayout();
            // 
            // MainTab
            // 
            this.MainTab.Controls.Add(this.ArcanTP);
            this.MainTab.Controls.Add(this.DatabaseTP);
            this.MainTab.Controls.Add(this.OutputTP);
            this.MainTab.Location = new System.Drawing.Point(1, 1);
            this.MainTab.Name = "MainTab";
            this.MainTab.SelectedIndex = 0;
            this.MainTab.Size = new System.Drawing.Size(618, 314);
            this.MainTab.SizeMode = System.Windows.Forms.TabSizeMode.FillToRight;
            this.MainTab.TabIndex = 0;
            this.MainTab.SelectedIndexChanged += new System.EventHandler(this.MainTab_TabIndexChanged);
            // 
            // ArcanTP
            // 
            this.ArcanTP.Controls.Add(this.BASEBTN);
            this.ArcanTP.Controls.Add(this.BasedirTB);
            this.ArcanTP.Controls.Add(this.label7);
            this.ArcanTP.Controls.Add(this.PrewakeSelector);
            this.ArcanTP.Controls.Add(this.ThemePathTB);
            this.ArcanTP.Controls.Add(this.ResourcePathTB);
            this.ArcanTP.Controls.Add(this.DatabaseTB);
            this.ArcanTP.Controls.Add(this.ySelector);
            this.ArcanTP.Controls.Add(this.xSelector);
            this.ArcanTP.Controls.Add(this.label8);
            this.ArcanTP.Controls.Add(this.HeightSelector);
            this.ArcanTP.Controls.Add(this.label6);
            this.ArcanTP.Controls.Add(this.WidthSelector);
            this.ArcanTP.Controls.Add(this.label5);
            this.ArcanTP.Controls.Add(this.LaunchArcanBTN);
            this.ArcanTP.Controls.Add(this.CMDLine);
            this.ArcanTP.Controls.Add(this.SilentCB);
            this.ArcanTP.Controls.Add(this.ConservativeCB);
            this.ArcanTP.Controls.Add(this.WaitSleepCB);
            this.ArcanTP.Controls.Add(this.VSYNCCB);
            this.ArcanTP.Controls.Add(this.DBBTN);
            this.ArcanTP.Controls.Add(this.label1);
            this.ArcanTP.Controls.Add(this.TPathBTN);
            this.ArcanTP.Controls.Add(this.RPathBTN);
            this.ArcanTP.Controls.Add(this.ThemeList);
            this.ArcanTP.Controls.Add(this.NoBorderCB);
            this.ArcanTP.Controls.Add(this.FullscreenCB);
            this.ArcanTP.Location = new System.Drawing.Point(4, 22);
            this.ArcanTP.Name = "ArcanTP";
            this.ArcanTP.Padding = new System.Windows.Forms.Padding(3);
            this.ArcanTP.Size = new System.Drawing.Size(610, 288);
            this.ArcanTP.TabIndex = 0;
            this.ArcanTP.Text = "Arcan";
            this.ArcanTP.UseVisualStyleBackColor = true;
            // 
            // BASEBTN
            // 
            this.BASEBTN.Location = new System.Drawing.Point(363, 180);
            this.BASEBTN.Name = "BASEBTN";
            this.BASEBTN.Size = new System.Drawing.Size(118, 21);
            this.BASEBTN.TabIndex = 33;
            this.BASEBTN.Text = "Base Directory...";
            this.BASEBTN.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
            this.BASEBTN.UseVisualStyleBackColor = true;
            this.BASEBTN.Click += new System.EventHandler(this.BASEBTN_Click);
            // 
            // BasedirTB
            // 
            this.BasedirTB.Enabled = false;
            this.BasedirTB.Location = new System.Drawing.Point(11, 180);
            this.BasedirTB.Name = "BasedirTB";
            this.BasedirTB.Size = new System.Drawing.Size(346, 20);
            this.BasedirTB.TabIndex = 32;
            // 
            // label7
            // 
            this.label7.AutoSize = true;
            this.label7.Location = new System.Drawing.Point(350, 118);
            this.label7.Name = "label7";
            this.label7.Size = new System.Drawing.Size(52, 13);
            this.label7.TabIndex = 31;
            this.label7.Text = "Prewake:";
            // 
            // PrewakeSelector
            // 
            this.PrewakeSelector.DecimalPlaces = 1;
            this.PrewakeSelector.Increment = new decimal(new int[] {
            1,
            0,
            0,
            65536});
            this.PrewakeSelector.Location = new System.Drawing.Point(406, 116);
            this.PrewakeSelector.Maximum = new decimal(new int[] {
            10,
            0,
            0,
            65536});
            this.PrewakeSelector.Minimum = new decimal(new int[] {
            1,
            0,
            0,
            65536});
            this.PrewakeSelector.Name = "PrewakeSelector";
            this.PrewakeSelector.Size = new System.Drawing.Size(61, 20);
            this.PrewakeSelector.TabIndex = 30;
            this.PrewakeSelector.Value = new decimal(new int[] {
            6,
            0,
            0,
            65536});
            this.PrewakeSelector.ValueChanged += new System.EventHandler(this.cmdLineUpdated);
            // 
            // ThemePathTB
            // 
            this.ThemePathTB.Enabled = false;
            this.ThemePathTB.Location = new System.Drawing.Point(11, 262);
            this.ThemePathTB.Name = "ThemePathTB";
            this.ThemePathTB.Size = new System.Drawing.Size(346, 20);
            this.ThemePathTB.TabIndex = 29;
            // 
            // ResourcePathTB
            // 
            this.ResourcePathTB.Enabled = false;
            this.ResourcePathTB.Location = new System.Drawing.Point(11, 236);
            this.ResourcePathTB.Name = "ResourcePathTB";
            this.ResourcePathTB.Size = new System.Drawing.Size(346, 20);
            this.ResourcePathTB.TabIndex = 28;
            // 
            // DatabaseTB
            // 
            this.DatabaseTB.Enabled = false;
            this.DatabaseTB.Location = new System.Drawing.Point(11, 210);
            this.DatabaseTB.Name = "DatabaseTB";
            this.DatabaseTB.Size = new System.Drawing.Size(346, 20);
            this.DatabaseTB.TabIndex = 27;
            // 
            // ySelector
            // 
            this.ySelector.Increment = new decimal(new int[] {
            2,
            0,
            0,
            0});
            this.ySelector.Location = new System.Drawing.Point(283, 142);
            this.ySelector.Maximum = new decimal(new int[] {
            2048,
            0,
            0,
            0});
            this.ySelector.Name = "ySelector";
            this.ySelector.Size = new System.Drawing.Size(61, 20);
            this.ySelector.TabIndex = 26;
            this.ySelector.Value = new decimal(new int[] {
            100,
            0,
            0,
            0});
            this.ySelector.ValueChanged += new System.EventHandler(this.cmdLineUpdated);
            // 
            // xSelector
            // 
            this.xSelector.Increment = new decimal(new int[] {
            2,
            0,
            0,
            0});
            this.xSelector.Location = new System.Drawing.Point(216, 142);
            this.xSelector.Maximum = new decimal(new int[] {
            2048,
            0,
            0,
            0});
            this.xSelector.Name = "xSelector";
            this.xSelector.Size = new System.Drawing.Size(61, 20);
            this.xSelector.TabIndex = 25;
            this.xSelector.Value = new decimal(new int[] {
            100,
            0,
            0,
            0});
            this.xSelector.ValueChanged += new System.EventHandler(this.cmdLineUpdated);
            // 
            // label8
            // 
            this.label8.AutoSize = true;
            this.label8.Location = new System.Drawing.Point(130, 144);
            this.label8.Name = "label8";
            this.label8.Size = new System.Drawing.Size(77, 13);
            this.label8.TabIndex = 24;
            this.label8.Text = "Window X / Y:";
            // 
            // HeightSelector
            // 
            this.HeightSelector.Increment = new decimal(new int[] {
            2,
            0,
            0,
            0});
            this.HeightSelector.Location = new System.Drawing.Point(283, 116);
            this.HeightSelector.Maximum = new decimal(new int[] {
            2048,
            0,
            0,
            0});
            this.HeightSelector.Minimum = new decimal(new int[] {
            200,
            0,
            0,
            0});
            this.HeightSelector.Name = "HeightSelector";
            this.HeightSelector.Size = new System.Drawing.Size(61, 20);
            this.HeightSelector.TabIndex = 22;
            this.HeightSelector.Value = new decimal(new int[] {
            480,
            0,
            0,
            0});
            // 
            // label6
            // 
            this.label6.AutoSize = true;
            this.label6.Location = new System.Drawing.Point(130, 118);
            this.label6.Name = "label6";
            this.label6.Size = new System.Drawing.Size(80, 13);
            this.label6.TabIndex = 21;
            this.label6.Text = "Width / Height:";
            // 
            // WidthSelector
            // 
            this.WidthSelector.Increment = new decimal(new int[] {
            2,
            0,
            0,
            0});
            this.WidthSelector.Location = new System.Drawing.Point(216, 116);
            this.WidthSelector.Maximum = new decimal(new int[] {
            2048,
            0,
            0,
            0});
            this.WidthSelector.Minimum = new decimal(new int[] {
            320,
            0,
            0,
            0});
            this.WidthSelector.Name = "WidthSelector";
            this.WidthSelector.Size = new System.Drawing.Size(61, 20);
            this.WidthSelector.TabIndex = 20;
            this.WidthSelector.Value = new decimal(new int[] {
            640,
            0,
            0,
            0});
            this.WidthSelector.ValueChanged += new System.EventHandler(this.cmdLineUpdated);
            // 
            // label5
            // 
            this.label5.AutoSize = true;
            this.label5.Location = new System.Drawing.Point(14, 5);
            this.label5.Name = "label5";
            this.label5.Size = new System.Drawing.Size(80, 13);
            this.label5.TabIndex = 19;
            this.label5.Text = "Command Line:";
            // 
            // LaunchArcanBTN
            // 
            this.LaunchArcanBTN.Location = new System.Drawing.Point(443, 21);
            this.LaunchArcanBTN.Name = "LaunchArcanBTN";
            this.LaunchArcanBTN.Size = new System.Drawing.Size(38, 23);
            this.LaunchArcanBTN.TabIndex = 18;
            this.LaunchArcanBTN.Text = "Go";
            this.LaunchArcanBTN.UseVisualStyleBackColor = true;
            this.LaunchArcanBTN.Click += new System.EventHandler(this.LaunchArcanBTN_Click);
            // 
            // CMDLine
            // 
            this.CMDLine.Location = new System.Drawing.Point(11, 21);
            this.CMDLine.Name = "CMDLine";
            this.CMDLine.Size = new System.Drawing.Size(425, 20);
            this.CMDLine.TabIndex = 17;
            // 
            // SilentCB
            // 
            this.SilentCB.AutoSize = true;
            this.SilentCB.Location = new System.Drawing.Point(133, 94);
            this.SilentCB.Name = "SilentCB";
            this.SilentCB.Size = new System.Drawing.Size(114, 17);
            this.SilentCB.TabIndex = 16;
            this.SilentCB.Text = "0 Db Audio Output";
            this.SilentCB.UseVisualStyleBackColor = true;
            this.SilentCB.CheckedChanged += new System.EventHandler(this.cmdLineUpdated);
            // 
            // ConservativeCB
            // 
            this.ConservativeCB.AutoSize = true;
            this.ConservativeCB.Location = new System.Drawing.Point(133, 71);
            this.ConservativeCB.Name = "ConservativeCB";
            this.ConservativeCB.Size = new System.Drawing.Size(160, 17);
            this.ConservativeCB.TabIndex = 15;
            this.ConservativeCB.Text = "Conservative Memory Profile";
            this.ConservativeCB.UseVisualStyleBackColor = true;
            this.ConservativeCB.CheckedChanged += new System.EventHandler(this.cmdLineUpdated);
            // 
            // WaitSleepCB
            // 
            this.WaitSleepCB.AutoSize = true;
            this.WaitSleepCB.Location = new System.Drawing.Point(11, 140);
            this.WaitSleepCB.Name = "WaitSleepCB";
            this.WaitSleepCB.Size = new System.Drawing.Size(78, 17);
            this.WaitSleepCB.TabIndex = 10;
            this.WaitSleepCB.Text = "Wait Sleep";
            this.WaitSleepCB.UseVisualStyleBackColor = true;
            this.WaitSleepCB.CheckedChanged += new System.EventHandler(this.cmdLineUpdated);
            // 
            // VSYNCCB
            // 
            this.VSYNCCB.AutoSize = true;
            this.VSYNCCB.Location = new System.Drawing.Point(11, 117);
            this.VSYNCCB.Name = "VSYNCCB";
            this.VSYNCCB.Size = new System.Drawing.Size(62, 17);
            this.VSYNCCB.TabIndex = 9;
            this.VSYNCCB.Text = "VSYNC";
            this.VSYNCCB.UseVisualStyleBackColor = true;
            this.VSYNCCB.CheckedChanged += new System.EventHandler(this.cmdLineUpdated);
            // 
            // DBBTN
            // 
            this.DBBTN.Location = new System.Drawing.Point(363, 207);
            this.DBBTN.Name = "DBBTN";
            this.DBBTN.Size = new System.Drawing.Size(118, 21);
            this.DBBTN.TabIndex = 7;
            this.DBBTN.Text = "Database...";
            this.DBBTN.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
            this.DBBTN.UseVisualStyleBackColor = true;
            this.DBBTN.Click += new System.EventHandler(this.DBBTN_Click);
            // 
            // label1
            // 
            this.label1.AutoSize = true;
            this.label1.Location = new System.Drawing.Point(487, 3);
            this.label1.Name = "label1";
            this.label1.Size = new System.Drawing.Size(76, 13);
            this.label1.TabIndex = 6;
            this.label1.Text = "Active Theme:";
            // 
            // TPathBTN
            // 
            this.TPathBTN.Location = new System.Drawing.Point(363, 261);
            this.TPathBTN.Name = "TPathBTN";
            this.TPathBTN.Size = new System.Drawing.Size(118, 21);
            this.TPathBTN.TabIndex = 5;
            this.TPathBTN.Text = "Theme Path...";
            this.TPathBTN.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
            this.TPathBTN.UseVisualStyleBackColor = true;
            this.TPathBTN.Click += new System.EventHandler(this.TPathBTN_Click);
            // 
            // RPathBTN
            // 
            this.RPathBTN.Location = new System.Drawing.Point(363, 234);
            this.RPathBTN.Name = "RPathBTN";
            this.RPathBTN.Size = new System.Drawing.Size(118, 21);
            this.RPathBTN.TabIndex = 4;
            this.RPathBTN.Text = "Resource Path...";
            this.RPathBTN.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
            this.RPathBTN.UseVisualStyleBackColor = true;
            this.RPathBTN.Click += new System.EventHandler(this.RPathBTN_Click);
            // 
            // ThemeList
            // 
            this.ThemeList.FormattingEnabled = true;
            this.ThemeList.Location = new System.Drawing.Point(487, 21);
            this.ThemeList.Name = "ThemeList";
            this.ThemeList.Size = new System.Drawing.Size(127, 264);
            this.ThemeList.TabIndex = 3;
            this.ThemeList.SelectedIndexChanged += new System.EventHandler(this.cmdLineUpdated);
            this.ThemeList.CursorChanged += new System.EventHandler(this.cmdLineUpdated);
            // 
            // NoBorderCB
            // 
            this.NoBorderCB.AutoSize = true;
            this.NoBorderCB.Location = new System.Drawing.Point(11, 71);
            this.NoBorderCB.Name = "NoBorderCB";
            this.NoBorderCB.Size = new System.Drawing.Size(95, 17);
            this.NoBorderCB.TabIndex = 2;
            this.NoBorderCB.Text = "Disable Border";
            this.NoBorderCB.UseVisualStyleBackColor = true;
            this.NoBorderCB.CheckedChanged += new System.EventHandler(this.cmdLineUpdated);
            // 
            // FullscreenCB
            // 
            this.FullscreenCB.AutoSize = true;
            this.FullscreenCB.Location = new System.Drawing.Point(11, 94);
            this.FullscreenCB.Name = "FullscreenCB";
            this.FullscreenCB.Size = new System.Drawing.Size(74, 17);
            this.FullscreenCB.TabIndex = 1;
            this.FullscreenCB.Text = "Fullscreen";
            this.FullscreenCB.UseVisualStyleBackColor = true;
            this.FullscreenCB.CheckedChanged += new System.EventHandler(this.cmdLineUpdated);
            // 
            // DatabaseTP
            // 
            this.DatabaseTP.Controls.Add(this.DBTgtDbBTN);
            this.DatabaseTP.Controls.Add(this.tabControl1);
            this.DatabaseTP.Controls.Add(this.label4);
            this.DatabaseTP.Controls.Add(this.DbResBTN);
            this.DatabaseTP.Controls.Add(this.resPathTB);
            this.DatabaseTP.Controls.Add(this.BuildBTN);
            this.DatabaseTP.Controls.Add(this.label3);
            this.DatabaseTP.Controls.Add(this.TargetDatabaseTB);
            this.DatabaseTP.Location = new System.Drawing.Point(4, 22);
            this.DatabaseTP.Name = "DatabaseTP";
            this.DatabaseTP.Padding = new System.Windows.Forms.Padding(3);
            this.DatabaseTP.Size = new System.Drawing.Size(610, 288);
            this.DatabaseTP.TabIndex = 1;
            this.DatabaseTP.Text = "Database";
            this.DatabaseTP.UseVisualStyleBackColor = true;
            // 
            // DBTgtDbBTN
            // 
            this.DBTgtDbBTN.Location = new System.Drawing.Point(224, 20);
            this.DBTgtDbBTN.Name = "DBTgtDbBTN";
            this.DBTgtDbBTN.Size = new System.Drawing.Size(75, 23);
            this.DBTgtDbBTN.TabIndex = 10;
            this.DBTgtDbBTN.Text = "Change...";
            this.DBTgtDbBTN.UseVisualStyleBackColor = true;
            this.DBTgtDbBTN.Click += new System.EventHandler(this.DBTgtDbBTN_Click);
            // 
            // tabControl1
            // 
            this.tabControl1.Controls.Add(this.tabPage1);
            this.tabControl1.Controls.Add(this.tabPage3);
            this.tabControl1.Controls.Add(this.tabPage4);
            this.tabControl1.Controls.Add(this.tabPage5);
            this.tabControl1.Location = new System.Drawing.Point(8, 89);
            this.tabControl1.Name = "tabControl1";
            this.tabControl1.SelectedIndex = 0;
            this.tabControl1.Size = new System.Drawing.Size(594, 193);
            this.tabControl1.TabIndex = 9;
            // 
            // tabPage1
            // 
            this.tabPage1.Controls.Add(this.TargetsLB);
            this.tabPage1.Controls.Add(this.skipRB);
            this.tabPage1.Controls.Add(this.scanRB);
            this.tabPage1.Controls.Add(this.UpdateOnlyCB);
            this.tabPage1.Controls.Add(this.DisableGenericCB);
            this.tabPage1.Location = new System.Drawing.Point(4, 22);
            this.tabPage1.Name = "tabPage1";
            this.tabPage1.Padding = new System.Windows.Forms.Padding(3);
            this.tabPage1.Size = new System.Drawing.Size(586, 167);
            this.tabPage1.TabIndex = 0;
            this.tabPage1.Text = "Generic Options";
            this.tabPage1.UseVisualStyleBackColor = true;
            // 
            // TargetsLB
            // 
            this.TargetsLB.FormattingEnabled = true;
            this.TargetsLB.Location = new System.Drawing.Point(441, 6);
            this.TargetsLB.Name = "TargetsLB";
            this.TargetsLB.SelectionMode = System.Windows.Forms.SelectionMode.MultiSimple;
            this.TargetsLB.Size = new System.Drawing.Size(139, 160);
            this.TargetsLB.TabIndex = 4;
            // 
            // skipRB
            // 
            this.skipRB.AutoSize = true;
            this.skipRB.Checked = true;
            this.skipRB.Location = new System.Drawing.Point(389, 30);
            this.skipRB.Name = "skipRB";
            this.skipRB.Size = new System.Drawing.Size(46, 17);
            this.skipRB.TabIndex = 3;
            this.skipRB.TabStop = true;
            this.skipRB.Text = "Skip";
            this.skipRB.UseVisualStyleBackColor = true;
            // 
            // scanRB
            // 
            this.scanRB.AutoSize = true;
            this.scanRB.Location = new System.Drawing.Point(389, 7);
            this.scanRB.Name = "scanRB";
            this.scanRB.Size = new System.Drawing.Size(50, 17);
            this.scanRB.TabIndex = 2;
            this.scanRB.Text = "Scan";
            this.scanRB.UseVisualStyleBackColor = true;
            // 
            // UpdateOnlyCB
            // 
            this.UpdateOnlyCB.AutoSize = true;
            this.UpdateOnlyCB.Location = new System.Drawing.Point(6, 29);
            this.UpdateOnlyCB.Name = "UpdateOnlyCB";
            this.UpdateOnlyCB.Size = new System.Drawing.Size(85, 17);
            this.UpdateOnlyCB.TabIndex = 1;
            this.UpdateOnlyCB.Text = "Update Only";
            this.UpdateOnlyCB.UseVisualStyleBackColor = true;
            // 
            // DisableGenericCB
            // 
            this.DisableGenericCB.AutoSize = true;
            this.DisableGenericCB.Location = new System.Drawing.Point(6, 6);
            this.DisableGenericCB.Name = "DisableGenericCB";
            this.DisableGenericCB.Size = new System.Drawing.Size(185, 17);
            this.DisableGenericCB.TabIndex = 0;
            this.DisableGenericCB.Text = "Disable Generic Fallback Importer";
            this.DisableGenericCB.UseVisualStyleBackColor = true;
            // 
            // tabPage3
            // 
            this.tabPage3.Controls.Add(this.ScrapeMetaMedia);
            this.tabPage3.Controls.Add(this.ScrapeMeta);
            this.tabPage3.Controls.Add(this.NoStripCB);
            this.tabPage3.Location = new System.Drawing.Point(4, 22);
            this.tabPage3.Name = "tabPage3";
            this.tabPage3.Padding = new System.Windows.Forms.Padding(3);
            this.tabPage3.Size = new System.Drawing.Size(586, 167);
            this.tabPage3.TabIndex = 1;
            this.tabPage3.Text = "Generic Importer";
            this.tabPage3.UseVisualStyleBackColor = true;
            // 
            // ScrapeMetaMedia
            // 
            this.ScrapeMetaMedia.AutoSize = true;
            this.ScrapeMetaMedia.Location = new System.Drawing.Point(6, 52);
            this.ScrapeMetaMedia.Name = "ScrapeMetaMedia";
            this.ScrapeMetaMedia.Size = new System.Drawing.Size(149, 17);
            this.ScrapeMetaMedia.TabIndex = 2;
            this.ScrapeMetaMedia.Text = "Scrape Media (GamesDB)";
            this.ScrapeMetaMedia.UseVisualStyleBackColor = true;
            // 
            // ScrapeMeta
            // 
            this.ScrapeMeta.AutoSize = true;
            this.ScrapeMeta.Location = new System.Drawing.Point(6, 29);
            this.ScrapeMeta.Name = "ScrapeMeta";
            this.ScrapeMeta.Size = new System.Drawing.Size(165, 17);
            this.ScrapeMeta.TabIndex = 1;
            this.ScrapeMeta.Text = "Scrape Metadata (GamesDB)";
            this.ScrapeMeta.UseVisualStyleBackColor = true;
            // 
            // NoStripCB
            // 
            this.NoStripCB.AutoSize = true;
            this.NoStripCB.Location = new System.Drawing.Point(6, 6);
            this.NoStripCB.Name = "NoStripCB";
            this.NoStripCB.Size = new System.Drawing.Size(119, 17);
            this.NoStripCB.TabIndex = 0;
            this.NoStripCB.Text = "Don\'t Shorten Titles";
            this.NoStripCB.UseVisualStyleBackColor = true;
            // 
            // tabPage4
            // 
            this.tabPage4.Controls.Add(this.MameGoodCB);
            this.tabPage4.Controls.Add(this.ShortenTitlesCB);
            this.tabPage4.Controls.Add(this.MameSkipCloneCB);
            this.tabPage4.Controls.Add(this.forceVerifyCB);
            this.tabPage4.Location = new System.Drawing.Point(4, 22);
            this.tabPage4.Name = "tabPage4";
            this.tabPage4.Size = new System.Drawing.Size(586, 167);
            this.tabPage4.TabIndex = 2;
            this.tabPage4.Text = "MAME Importer";
            this.tabPage4.UseVisualStyleBackColor = true;
            // 
            // MameGoodCB
            // 
            this.MameGoodCB.AutoSize = true;
            this.MameGoodCB.Checked = true;
            this.MameGoodCB.CheckState = System.Windows.Forms.CheckState.Checked;
            this.MameGoodCB.Location = new System.Drawing.Point(14, 85);
            this.MameGoodCB.Name = "MameGoodCB";
            this.MameGoodCB.Size = new System.Drawing.Size(121, 17);
            this.MameGoodCB.TabIndex = 3;
            this.MameGoodCB.Text = "Only \'Good\' Flagged";
            this.MameGoodCB.UseVisualStyleBackColor = true;
            // 
            // ShortenTitlesCB
            // 
            this.ShortenTitlesCB.AutoSize = true;
            this.ShortenTitlesCB.Checked = true;
            this.ShortenTitlesCB.CheckState = System.Windows.Forms.CheckState.Checked;
            this.ShortenTitlesCB.Location = new System.Drawing.Point(14, 62);
            this.ShortenTitlesCB.Name = "ShortenTitlesCB";
            this.ShortenTitlesCB.Size = new System.Drawing.Size(91, 17);
            this.ShortenTitlesCB.TabIndex = 2;
            this.ShortenTitlesCB.Text = "Shorten Titles";
            this.ShortenTitlesCB.UseVisualStyleBackColor = true;
            // 
            // MameSkipCloneCB
            // 
            this.MameSkipCloneCB.AutoSize = true;
            this.MameSkipCloneCB.Checked = true;
            this.MameSkipCloneCB.CheckState = System.Windows.Forms.CheckState.Checked;
            this.MameSkipCloneCB.Location = new System.Drawing.Point(14, 39);
            this.MameSkipCloneCB.Name = "MameSkipCloneCB";
            this.MameSkipCloneCB.Size = new System.Drawing.Size(82, 17);
            this.MameSkipCloneCB.TabIndex = 1;
            this.MameSkipCloneCB.Text = "Skip Clones";
            this.MameSkipCloneCB.UseVisualStyleBackColor = true;
            // 
            // forceVerifyCB
            // 
            this.forceVerifyCB.AutoSize = true;
            this.forceVerifyCB.Location = new System.Drawing.Point(14, 16);
            this.forceVerifyCB.Name = "forceVerifyCB";
            this.forceVerifyCB.Size = new System.Drawing.Size(82, 17);
            this.forceVerifyCB.TabIndex = 0;
            this.forceVerifyCB.Text = "Force Verify";
            this.forceVerifyCB.UseVisualStyleBackColor = true;
            // 
            // tabPage5
            // 
            this.tabPage5.Controls.Add(this.ShortenTitles);
            this.tabPage5.Controls.Add(this.FBSkipClonesCB);
            this.tabPage5.Location = new System.Drawing.Point(4, 22);
            this.tabPage5.Name = "tabPage5";
            this.tabPage5.Size = new System.Drawing.Size(586, 167);
            this.tabPage5.TabIndex = 3;
            this.tabPage5.Text = "FBA (libretro) Importer";
            this.tabPage5.UseVisualStyleBackColor = true;
            // 
            // ShortenTitles
            // 
            this.ShortenTitles.AutoSize = true;
            this.ShortenTitles.Checked = true;
            this.ShortenTitles.CheckState = System.Windows.Forms.CheckState.Checked;
            this.ShortenTitles.Location = new System.Drawing.Point(6, 26);
            this.ShortenTitles.Name = "ShortenTitles";
            this.ShortenTitles.Size = new System.Drawing.Size(91, 17);
            this.ShortenTitles.TabIndex = 1;
            this.ShortenTitles.Text = "Shorten Titles";
            this.ShortenTitles.UseVisualStyleBackColor = true;
            // 
            // FBSkipClonesCB
            // 
            this.FBSkipClonesCB.AutoSize = true;
            this.FBSkipClonesCB.Checked = true;
            this.FBSkipClonesCB.CheckState = System.Windows.Forms.CheckState.Checked;
            this.FBSkipClonesCB.Location = new System.Drawing.Point(6, 3);
            this.FBSkipClonesCB.Name = "FBSkipClonesCB";
            this.FBSkipClonesCB.Size = new System.Drawing.Size(82, 17);
            this.FBSkipClonesCB.TabIndex = 0;
            this.FBSkipClonesCB.Text = "Skip Clones";
            this.FBSkipClonesCB.UseVisualStyleBackColor = true;
            // 
            // label4
            // 
            this.label4.AutoSize = true;
            this.label4.Location = new System.Drawing.Point(8, 46);
            this.label4.Name = "label4";
            this.label4.Size = new System.Drawing.Size(81, 13);
            this.label4.TabIndex = 8;
            this.label4.Text = "Resource Path:";
            // 
            // DbResBTN
            // 
            this.DbResBTN.Location = new System.Drawing.Point(224, 60);
            this.DbResBTN.Name = "DbResBTN";
            this.DbResBTN.Size = new System.Drawing.Size(75, 23);
            this.DbResBTN.TabIndex = 7;
            this.DbResBTN.Text = "Change...";
            this.DbResBTN.UseVisualStyleBackColor = true;
            this.DbResBTN.Click += new System.EventHandler(this.DbResBTN_Click);
            // 
            // resPathTB
            // 
            this.resPathTB.Enabled = false;
            this.resPathTB.Location = new System.Drawing.Point(11, 63);
            this.resPathTB.Name = "resPathTB";
            this.resPathTB.Size = new System.Drawing.Size(207, 20);
            this.resPathTB.TabIndex = 6;
            // 
            // BuildBTN
            // 
            this.BuildBTN.Location = new System.Drawing.Point(492, 63);
            this.BuildBTN.Name = "BuildBTN";
            this.BuildBTN.Size = new System.Drawing.Size(103, 23);
            this.BuildBTN.TabIndex = 5;
            this.BuildBTN.Text = "Build Database";
            this.BuildBTN.UseVisualStyleBackColor = true;
            this.BuildBTN.Click += new System.EventHandler(this.BuildBTN_Click);
            // 
            // label3
            // 
            this.label3.AutoSize = true;
            this.label3.Location = new System.Drawing.Point(8, 7);
            this.label3.Name = "label3";
            this.label3.Size = new System.Drawing.Size(90, 13);
            this.label3.TabIndex = 4;
            this.label3.Text = "Target Database:";
            // 
            // TargetDatabaseTB
            // 
            this.TargetDatabaseTB.Enabled = false;
            this.TargetDatabaseTB.Location = new System.Drawing.Point(11, 23);
            this.TargetDatabaseTB.Name = "TargetDatabaseTB";
            this.TargetDatabaseTB.Size = new System.Drawing.Size(207, 20);
            this.TargetDatabaseTB.TabIndex = 3;
            // 
            // OutputTP
            // 
            this.OutputTP.Controls.Add(this.OutputErrLB);
            this.OutputTP.Controls.Add(this.outputLB);
            this.OutputTP.Location = new System.Drawing.Point(4, 22);
            this.OutputTP.Name = "OutputTP";
            this.OutputTP.Size = new System.Drawing.Size(610, 288);
            this.OutputTP.TabIndex = 2;
            this.OutputTP.Text = "Output";
            this.OutputTP.UseVisualStyleBackColor = true;
            // 
            // OutputErrLB
            // 
            this.OutputErrLB.FormattingEnabled = true;
            this.OutputErrLB.Location = new System.Drawing.Point(300, 15);
            this.OutputErrLB.Name = "OutputErrLB";
            this.OutputErrLB.ScrollAlwaysVisible = true;
            this.OutputErrLB.Size = new System.Drawing.Size(310, 277);
            this.OutputErrLB.TabIndex = 1;
            // 
            // outputLB
            // 
            this.outputLB.FormattingEnabled = true;
            this.outputLB.Location = new System.Drawing.Point(-4, 15);
            this.outputLB.Name = "outputLB";
            this.outputLB.ScrollAlwaysVisible = true;
            this.outputLB.Size = new System.Drawing.Size(302, 277);
            this.outputLB.TabIndex = 0;
            // 
            // dbSelector
            // 
            this.dbSelector.FileName = "openFileDialog1";
            // 
            // newdbSelector
            // 
            this.newdbSelector.CheckFileExists = false;
            this.newdbSelector.FileName = "openFileDialog1";
            // 
            // LauncherForm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(621, 314);
            this.Controls.Add(this.MainTab);
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedSingle;
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.MaximizeBox = false;
            this.Name = "LauncherForm";
            this.Text = "Arcan Launcher";
            this.MainTab.ResumeLayout(false);
            this.ArcanTP.ResumeLayout(false);
            this.ArcanTP.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.PrewakeSelector)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.ySelector)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.xSelector)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.HeightSelector)).EndInit();
            ((System.ComponentModel.ISupportInitialize)(this.WidthSelector)).EndInit();
            this.DatabaseTP.ResumeLayout(false);
            this.DatabaseTP.PerformLayout();
            this.tabControl1.ResumeLayout(false);
            this.tabPage1.ResumeLayout(false);
            this.tabPage1.PerformLayout();
            this.tabPage3.ResumeLayout(false);
            this.tabPage3.PerformLayout();
            this.tabPage4.ResumeLayout(false);
            this.tabPage4.PerformLayout();
            this.tabPage5.ResumeLayout(false);
            this.tabPage5.PerformLayout();
            this.OutputTP.ResumeLayout(false);
            this.ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.TabControl MainTab;
        private System.Windows.Forms.TabPage ArcanTP;
        private System.Windows.Forms.TabPage DatabaseTP;
        private System.Windows.Forms.Label label6;
        private System.Windows.Forms.NumericUpDown WidthSelector;
        private System.Windows.Forms.Label label5;
        private System.Windows.Forms.Button LaunchArcanBTN;
        private System.Windows.Forms.TextBox CMDLine;
        private System.Windows.Forms.CheckBox SilentCB;
        private System.Windows.Forms.CheckBox ConservativeCB;
        private System.Windows.Forms.CheckBox WaitSleepCB;
        private System.Windows.Forms.CheckBox VSYNCCB;
        private System.Windows.Forms.Button DBBTN;
        private System.Windows.Forms.Label label1;
        private System.Windows.Forms.Button TPathBTN;
        private System.Windows.Forms.Button RPathBTN;
        private System.Windows.Forms.CheckBox NoBorderCB;
        private System.Windows.Forms.CheckBox FullscreenCB;
        private System.Windows.Forms.FolderBrowserDialog folderSelector;
        private System.Windows.Forms.OpenFileDialog dbSelector;
        private System.Windows.Forms.NumericUpDown ySelector;
        private System.Windows.Forms.NumericUpDown xSelector;
        private System.Windows.Forms.Label label8;
        private System.Windows.Forms.NumericUpDown HeightSelector;
        private System.Windows.Forms.TabControl tabControl1;
        private System.Windows.Forms.TabPage tabPage1;
        private System.Windows.Forms.TabPage tabPage3;
        private System.Windows.Forms.TabPage tabPage4;
        private System.Windows.Forms.TabPage tabPage5;
        private System.Windows.Forms.Label label4;
        private System.Windows.Forms.Button DbResBTN;
        private System.Windows.Forms.TextBox resPathTB;
        private System.Windows.Forms.Button BuildBTN;
        private System.Windows.Forms.Label label3;
        private System.Windows.Forms.TextBox TargetDatabaseTB;
        private System.Windows.Forms.TextBox ThemePathTB;
        private System.Windows.Forms.TextBox ResourcePathTB;
        private System.Windows.Forms.TextBox DatabaseTB;
        private System.Windows.Forms.NumericUpDown PrewakeSelector;
        private System.Windows.Forms.Label label7;
        private System.Windows.Forms.ListBox ThemeList;
        private System.Windows.Forms.RadioButton skipRB;
        private System.Windows.Forms.RadioButton scanRB;
        private System.Windows.Forms.CheckBox UpdateOnlyCB;
        private System.Windows.Forms.CheckBox DisableGenericCB;
        private System.Windows.Forms.CheckBox ScrapeMetaMedia;
        private System.Windows.Forms.CheckBox ScrapeMeta;
        private System.Windows.Forms.CheckBox NoStripCB;
        private System.Windows.Forms.CheckBox MameGoodCB;
        private System.Windows.Forms.CheckBox ShortenTitlesCB;
        private System.Windows.Forms.CheckBox MameSkipCloneCB;
        private System.Windows.Forms.CheckBox forceVerifyCB;
        private System.Windows.Forms.TabPage OutputTP;
        private System.Windows.Forms.ListBox outputLB;
        private System.Windows.Forms.ListBox OutputErrLB;
        private System.Windows.Forms.Button DBTgtDbBTN;
        private System.Windows.Forms.OpenFileDialog newdbSelector;
        private System.Windows.Forms.ListBox TargetsLB;
        private System.Windows.Forms.CheckBox ShortenTitles;
        private System.Windows.Forms.CheckBox FBSkipClonesCB;
        private System.Windows.Forms.Button BASEBTN;
        private System.Windows.Forms.TextBox BasedirTB;
    }
}

