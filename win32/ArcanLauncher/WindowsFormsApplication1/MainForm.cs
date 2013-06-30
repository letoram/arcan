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
            InitializeComponent();
            String baseDir;

            Object baseDirObj = Registry.GetValue("HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Arcan", "InstallationDirectory", null);
            if (baseDirObj == null)
                baseDirObj = Registry.GetValue("HKEY_LOCAL_MACHINE\\Software\\Arcan", "InstallationDirectory", null);

            if (baseDirObj == null){
                baseDir = "C:\\Arcan";
            } else
                baseDir = (string) baseDirObj;

            DatabaseTB.Text = String.Format("{0}\\resources\\arcandb.sqlite", baseDir);
            ThemePathTB.Text = String.Format("{0}\\themes", baseDir);
            ResourcePathTB.Text = String.Format("{0}\\resources", baseDir);

            updateThemeList();
            RebuildCmdLine();
        }

        private void updateThemeList()
        {
            ThemeList.Items.Clear();
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
            CMDLine.Text = String.Format("-w {0} -h {1} -F {2} -x {3} -y {4}", WidthSelector.Value, HeightSelector.Value, 
                PrewakeSelector.Value, xSelector.Value, ySelector.Value);
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
            Process aProc = new Process();
            aProc.StartInfo.FileName = "C:\\arcan30\\arcan.exe";
            aProc.StartInfo.WorkingDirectory = "C:\\arcan30";
            aProc.StartInfo.Arguments = CMDLine.Text;
            aProc.StartInfo.CreateNoWindow = true;
            aProc.StartInfo.RedirectStandardError = true;
            aProc.StartInfo.UseShellExecute = false;
            aProc.StartInfo.RedirectStandardOutput = true;
            aProc.ErrorDataReceived  += ErrorReceived;
            aProc.OutputDataReceived += DataReceived;

            aProc.Start();
            aProc.BeginErrorReadLine();
            aProc.BeginOutputReadLine();
            aProc.WaitForExit();
        }

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

    }
}
