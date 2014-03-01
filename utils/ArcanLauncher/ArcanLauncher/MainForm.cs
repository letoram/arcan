using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.IO;
using System.Drawing;
using Microsoft.Win32;
using System.Linq;
using System.Text;
using System.Diagnostics;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace ArcanLauncher
{
    public partial class LauncherForm : Form
    {
        public LauncherForm()
        {
            String baseDir;

            InitializeComponent();
            
            List<String> paths = new List<String>();
            paths.Add(Directory.GetCurrentDirectory());
            paths.Add("C:\\Program Files (x86)\\Arcan");
            paths.Add("C:\\Program Files (x86)\\Arcan31");
            paths.Add("C:\\Program Files\\Arcan");
            paths.Add("C:\\Arcan");
            paths.Add("C:\\Arcan31");
             
/* try to locate the installation, should've had this key written: */
            Object baseDirObj = Registry.GetValue("HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Arcan", "InstallationDirectory", null);
            if (baseDirObj == null)
                baseDirObj = Registry.GetValue("HKEY_LOCAL_MACHINE\\Software\\Arcan", "InstallationDirectory", null);

            baseDir = (string)baseDirObj;

            if (baseDir == null || Directory.Exists(baseDir) == false)
                foreach (String val in paths) {
                    if (Directory.Exists(val)){
                        baseDir = val;
                        break;
                    }
                }

            if (baseDir != null && Directory.Exists(baseDir))
            {
                BasedirTB.Text = baseDir;
                DatabaseTB.Text = String.Format("{0}\\resources\\arcandb.sqlite", baseDir);
                ThemePathTB.Text = String.Format("{0}\\themes", baseDir);
                ResourcePathTB.Text = String.Format("{0}\\resources", baseDir);

                updateThemeList();
                RebuildCmdLine();
            }
            else
                BasedirTB.Text = "Not Found";
        }

        private void updateThemeList()
        {
            ThemeList.Items.Clear();
            if (Directory.Exists(ThemePathTB.Text) == false)
                ThemePathTB.Text = BasedirTB.Text + "\\themes";

            if (Directory.Exists(ThemePathTB.Text) == false)
                return;

            foreach (DirectoryInfo dirinf in (new DirectoryInfo(ThemePathTB.Text).EnumerateDirectories()))
            {
                if (File.Exists(String.Format("{0}\\{1}.lua", dirinf.FullName, dirinf.Name)))
                {
                    ThemeList.Items.Add(dirinf.Name);
                }
            }
        }

        public void RebuildCmdLine()
        {
            CMDLine.Text = String.Format("-w {0} -h {1} -F {2} -x {3} -y {4} -d \"{5}\"", WidthSelector.Value, HeightSelector.Value, 
                PrewakeSelector.Value, xSelector.Value, ySelector.Value, DatabaseTB.Text);
            if (NoBorderCB.Checked)
                CMDLine.Text += " -s";

            if (FullscreenCB.Checked)
                CMDLine.Text += " -f";

            if (ConservativeCB.Checked)
                CMDLine.Text += " -m";

            if (VSYNCCB.Checked)
                CMDLine.Text += " -v";

            if (WaitSleepCB.Checked)
                CMDLine.Text += " -V";

            if (SilentCB.Checked)
                CMDLine.Text += " -S";

            CMDLine.Text += String.Format(" -p \"{0}\" -t \"{1}\"", ResourcePathTB.Text, ThemePathTB.Text);
            //"-p \"{1}\" -t \"{2}\"", DatabaseTB.Text, ResourcePathTB.Text, ThemePathTB.Text);

            if (ThemeList.SelectedItem != null)
                CMDLine.Text += " " + ThemeList.SelectedItem.ToString();
                        
            /*
             * just sweep through the settings component and build a commandline string,
             * this will be combined (in the arcanBTN_Click) with the CWD (or regkey) + arcan.exe 
             */
        }

        private void DBBTN_Click(object sender, EventArgs e)
        {
            dbSelector.FileName = DatabaseTB.Text;
            DialogResult res = dbSelector.ShowDialog();
         
            if (res == DialogResult.OK){
                DatabaseTB.Text = dbSelector.FileName;
            }

            RebuildCmdLine();
        }

        private void LaunchArcanBTN_Click(object sender, EventArgs e)
        {
            OutputErrLB.Items.Clear();
            outputLB.Items.Clear();

            Process aProc = new Process();
            aProc.StartInfo.FileName = BasedirTB.Text + "\\arcan.exe";
            aProc.StartInfo.WorkingDirectory = BasedirTB.Text;
            aProc.StartInfo.Arguments = CMDLine.Text;
            aProc.StartInfo.CreateNoWindow = true;
            aProc.StartInfo.RedirectStandardError = true;
            aProc.StartInfo.UseShellExecute = false;
            aProc.StartInfo.RedirectStandardOutput = true;
            aProc.ErrorDataReceived  += ErrorReceived;
            aProc.OutputDataReceived += DataReceived;

            try
            {
                aProc.Start();
                aProc.BeginErrorReadLine();
                aProc.BeginOutputReadLine();
                aProc.WaitForExit();
            }
            finally
            {
                aProc.Close();
            }
        }

        delegate void LogPrinter(string p);

        private void ErrorReceived(object sender, DataReceivedEventArgs e)
        {
        }

        private void DataReceived(object sender, DataReceivedEventArgs e)
        {
        }

        private void cmdLineUpdated(object sender, EventArgs e)
        {
            RebuildCmdLine();
        }

        private void RPathBTN_Click(object sender, EventArgs e)
        {
            folderSelector.SelectedPath = ResourcePathTB.Text;
            DialogResult res = folderSelector.ShowDialog();

            if (res == DialogResult.OK)
            {
                ResourcePathTB.Text = folderSelector.SelectedPath;
            }

            RebuildCmdLine();
        }

        private void TPathBTN_Click(object sender, EventArgs e)
        {
            folderSelector.SelectedPath = ThemePathTB.Text;
            DialogResult res = folderSelector.ShowDialog();

            if (res == DialogResult.OK)
            {
                ThemePathTB.Text = folderSelector.SelectedPath;
            }

            updateThemeList();
            RebuildCmdLine();
        }

        private void GroupsChanged()
        {
            TargetsLB.Items.Clear();

            if (Directory.Exists(resPathTB.Text) == false)
                resPathTB.Text = BasedirTB.Text + "\\resources";

            if (Directory.Exists(resPathTB.Text + "\\targets") == false)
                return;

            foreach (FileInfo fileinf in (new DirectoryInfo(resPathTB.Text + "\\targets").EnumerateFiles()))
            {
                String basename = Path.GetFileNameWithoutExtension(fileinf.FullName);

                if (Directory.Exists(resPathTB.Text + "\\games\\" + basename))
                    TargetsLB.Items.Add(basename);
            }
        }

        private void MainTab_TabIndexChanged(object sender, EventArgs e)
        {
            if (MainTab.SelectedIndex == 1)
            {
                if (TargetDatabaseTB.Text.Length == 0)
                    TargetDatabaseTB.Text = DatabaseTB.Text;

                if (resPathTB.Text.Length == 0)
                    resPathTB.Text = ResourcePathTB.Text;

                GroupsChanged();
            }
        }

        private void DbResBTN_Click(object sender, EventArgs e)
        {
            folderSelector.SelectedPath = resPathTB.Text;
            DialogResult res = folderSelector.ShowDialog();

            if (res == DialogResult.OK)
            {
                resPathTB.Text = folderSelector.SelectedPath;
                GroupsChanged();
            }
        }

        private void DBTgtDbBTN_Click(object sender, EventArgs e)
        {
            newdbSelector.FileName = TargetDatabaseTB.Text;
            DialogResult res = newdbSelector.ShowDialog();

            if (res == DialogResult.OK)
            {
                TargetDatabaseTB.Text = newdbSelector.FileName;
            }
        }

        private void BuildBTN_Click(object sender, EventArgs e)
        {
            string CmdLine = String.Format("builddb --dbname \"{0}\" --rompath \"{1}\" --targetpath \"{2}\"",
                TargetDatabaseTB.Text.Replace(@"\", "/"), (resPathTB.Text + "\\games").Replace(@"\", "/"), (resPathTB.Text + "\\targets").Replace(@"\", "/"));

            if (DisableGenericCB.Checked)
                CmdLine += " --nogeneric";

            if (UpdateOnlyCB.Checked)
                CmdLine += " --update";

            if (TargetsLB.SelectedItems.Count > 0)
            {
                String basev = scanRB.Checked ? " --scangroup" : " --skipgroup";
                foreach (String val in TargetsLB.SelectedItems)
                {
                    CmdLine += basev + " " + val;
                }
            }

            if (!DisableGenericCB.Checked && NoStripCB.Checked)
                CmdLine += " --gennostriptitle";

            if (!DisableGenericCB.Checked && ScrapeMeta.Checked)
                CmdLine += " --genscrape";

            if (!DisableGenericCB.Checked && ScrapeMetaMedia.Checked)
                CmdLine += " --genscrapemedia";

            if (TargetsLB.Items.Contains("mame") || TargetsLB.Items.Contains("ume"))
            {
                if (forceVerifyCB.Checked)
                    CmdLine += " --mameverify";

                if (MameSkipCloneCB.Checked)
                    CmdLine += " --mameskipclone";

                if (MameGoodCB.Checked)
                    CmdLine += " --mamegood";

                if (ShortenTitlesCB.Checked)
                    CmdLine += " --mameshorttitle";
            }

            OutputErrLB.Items.Clear();
            outputLB.Items.Clear();

            Process aProc = new Process();
            aProc.StartInfo.FileName = BasedirTB.Text + "\\arcan_romman.exe";
            aProc.StartInfo.WorkingDirectory = BasedirTB.Text;
            aProc.StartInfo.Arguments = CmdLine;
            aProc.StartInfo.CreateNoWindow = false;
            aProc.StartInfo.RedirectStandardError = false;
            aProc.StartInfo.UseShellExecute = true;
            aProc.StartInfo.RedirectStandardOutput = false;
            MessageBox.Show(CmdLine);
            aProc.Start();
            aProc.WaitForExit();
        }

        private void BASEBTN_Click(object sender, EventArgs e)
        {
            folderSelector.SelectedPath = BasedirTB.Text;
            DialogResult res = folderSelector.ShowDialog();

            if (res == DialogResult.OK)
            {
                BasedirTB.Text = folderSelector.SelectedPath;
                GroupsChanged();
            }
        }
    }
}
