use anyhow::{anyhow, Context, Result};
use clap::{Parser, Subcommand};
use log::{debug, info};
use serde::Deserialize;
use std::path::{Path, PathBuf};
use std::process::Command;
use which::which;

/// Integration between Helix editor and Yazi file manager via WezTerm
#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Cli {
    /// Enable verbose logging
    #[arg(short, long)]
    verbose: bool,

    /// Path to wezterm executable
    #[arg(long)]
    wezterm_path: Option<PathBuf>,

    /// Path to yazi executable
    #[arg(long)]
    yazi_path: Option<PathBuf>,
    
    /// Path to custom Yazi config directory
    #[arg(long)]
    yazi_config_dir: Option<PathBuf>,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Open Yazi as a file picker from Helix
    OpenPicker {
        /// Current directory to open Yazi in (defaults to current working directory)
        #[arg(short, long)]
        dir: Option<String>,

        /// Width percentage of the Yazi pane (default: 40)
        #[arg(short, long, default_value = "40")]
        width: u32,

        /// Place file picker on left side (default) or right side
        #[arg(short, long, default_value = "left")]
        side: String,
        
        /// Path to WezTerm executable
        #[arg(long)]
        wezterm_path: Option<PathBuf>,
        
        /// Path to Yazi executable
        #[arg(long)]
        yazi_path: Option<PathBuf>,
        
        /// Path to custom Yazi config directory
        #[arg(long)]
        yazi_config_dir: Option<PathBuf>,
    },

    /// Open a file in Helix from Yazi
    OpenFile {
        /// Path to the file to open in Helix
        #[arg(required = true)]
        path: String,
        
        /// Path to WezTerm executable
        #[arg(long)]
        wezterm_path: Option<PathBuf>,
    },

    // Install command removed - configuration is handled by Home Manager
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct PaneSize {
    rows: u32,
    cols: u32,
    #[serde(rename = "pixel_width")]
    pixel_width: u32,
    #[serde(rename = "pixel_height")]
    pixel_height: u32,
    dpi: u32,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct WezTermPane {
    #[serde(rename = "window_id")]
    window_id: u64,
    #[serde(rename = "tab_id")]
    tab_id: u64,
    #[serde(rename = "pane_id")]
    pane_id: u64,
    workspace: String,
    size: PaneSize,
    title: String,
    cwd: String,
    #[serde(rename = "is_active")]
    is_active: bool,
    #[serde(rename = "is_zoomed")]
    is_zoomed: bool,
}

struct WezTermClient {
    wezterm_path: PathBuf,
}

impl WezTermClient {
    fn new(wezterm_path: Option<PathBuf>) -> Result<Self> {
        let executable = match wezterm_path {
            Some(path) => path,
            None => which("wezterm")
                .context("WezTerm not found in PATH")?,
        };

        Ok(Self {
            wezterm_path: executable,
        })
    }

    /// Find a terminal pane by direction from the current pane within the current tab
    fn get_pane_by_direction(&self, direction: &str) -> Result<String> {
        let output = Command::new(&self.wezterm_path)
            .args(["cli", "get-pane-direction", direction])
            .output()
            .context("Failed to execute wezterm cli get-pane-direction")?;

        if !output.status.success() {
            return Err(anyhow!(
                "wezterm cli command failed: {}",
                String::from_utf8_lossy(&output.stderr)
            ));
        }

        let pane_id = String::from_utf8(output.stdout)
            .context("Failed to parse wezterm output")?
            .trim()
            .to_string();

        if pane_id.is_empty() {
            Err(anyhow!("No pane found in direction: {}", direction))
        } else {
            Ok(pane_id)
        }
    }

    /// Get the current pane ID by parsing JSON output
    fn get_current_pane(&self) -> Result<String> {
        // Get a detailed list of panes in JSON format
        let output = Command::new(&self.wezterm_path)
            .args(["cli", "list", "--format=json"])
            .output()
            .context("Failed to list panes with wezterm cli list")?;

        if !output.status.success() {
            return Err(anyhow!("wezterm cli list failed: {}", 
                String::from_utf8_lossy(&output.stderr)));
        }

        let output_str = String::from_utf8(output.stdout)
            .context("Failed to parse wezterm cli list output")?;
        
        debug!("WezTerm CLI list JSON length: {} bytes", output_str.len());
        
        // Parse the JSON
        let panes: Vec<WezTermPane> = serde_json::from_str(&output_str)
            .context("Failed to parse JSON output from wezterm cli list")?;
        
        if panes.is_empty() {
            return Err(anyhow!("No panes found in wezterm output"));
        }
        
        // First, check if any pane is active in the current tab
        for pane in &panes {
            if pane.is_active {
                debug!("Found active pane: {}", pane.pane_id);
                return Ok(pane.pane_id.to_string());
            }
        }
        
        // Next, try to find a pane with helix in the title
        for pane in &panes {
            if pane.title.contains("hx") {
                debug!("Found helix pane: {}", pane.pane_id);
                return Ok(pane.pane_id.to_string());
            }
        }
        
        // If no active or helix pane found, use the first pane
        debug!("Using first available pane: {}", panes[0].pane_id);
        Ok(panes[0].pane_id.to_string())
    }

    /// Get panes only in the current tab
    fn get_panes_in_current_tab(&self) -> Result<Vec<String>> {
        // Get all panes in JSON format
        let output = Command::new(&self.wezterm_path)
            .args(["cli", "list", "--format=json"])
            .output()
            .context("Failed to list panes with wezterm cli list")?;

        if !output.status.success() {
            return Err(anyhow!("wezterm cli list failed: {}", 
                String::from_utf8_lossy(&output.stderr)));
        }

        let output_str = String::from_utf8(output.stdout)
            .context("Failed to parse wezterm cli list output")?;
        
        // Parse the JSON
        let panes: Vec<WezTermPane> = serde_json::from_str(&output_str)
            .context("Failed to parse JSON output from wezterm cli list")?;
        
        // Find the current tab ID by looking for active panes
        let mut current_tab_id = None;
        for pane in &panes {
            if pane.is_active {
                current_tab_id = Some(pane.tab_id);
                break;
            }
        }
        
        // If we couldn't find an active pane, use the first tab ID
        let tab_id = match current_tab_id {
            Some(id) => id,
            None => {
                if panes.is_empty() {
                    return Err(anyhow!("No panes found in wezterm output"));
                }
                panes[0].tab_id
            }
        };
        
        debug!("Using tab ID: {}", tab_id);
        
        // Filter only panes in this tab
        let tab_panes: Vec<String> = panes.iter()
            .filter(|pane| pane.tab_id == tab_id)
            .map(|pane| pane.pane_id.to_string())
            .collect();
        
        Ok(tab_panes)
    }

    /// Split a new pane and run a command with arguments directly in it with environment variables
///
/// This function creates a new pane in the specified direction with the given size,
/// sets environment variables for the command, and runs the command with its arguments.
///
/// # Arguments
///
/// * `direction` - The direction to split the pane ("left", "right", "top", "bottom")
/// * `percent` - The percentage of the screen the new pane should occupy
/// * `command_args` - The command and its arguments to run in the new pane
/// * `env_vars` - Environment variables to set for the command
///
/// # Returns
///
/// * The pane ID of the newly created pane on success
/// * An error if the pane creation or command execution fails
    fn split_pane_and_run_with_args(&self, direction: &str, percent: u32, command_args: &[&str], env_vars: &[(&str, &str)]) -> Result<String> {
        // Create a command builder directly
        let mut cmd = Command::new(&self.wezterm_path);
        
        // Set the environment variables for the wezterm process
        // These should be inherited by the command wezterm spawns
        for (key, value) in env_vars {
            cmd.env(key, value);
        }
        
        // Start with basic args
        cmd.arg("cli")
           .arg("split-pane")
           .arg(format!("--{}", direction))
           .arg("--percent")
           .arg(percent.to_string())
           .arg("--");
        
        // Add all command arguments separately to handle spaces properly
        for arg in command_args {
            cmd.arg(arg);
        }
        
        debug!("Running wezterm command with args: {:?} and env vars: {:?}", command_args, env_vars);
        
        // Execute the command
        let output = cmd.output()
            .context("Failed to execute wezterm cli split-pane with command")?;

        if !output.status.success() {
            return Err(anyhow!(
                "wezterm split-pane command with program failed: {}",
                String::from_utf8_lossy(&output.stderr)
            ));
        }

        Ok(String::from_utf8(output.stdout)
            .context("Failed to parse wezterm output")?
            .trim()
            .to_string())
    }

    /// Send text to a pane
    fn send_text_to_pane(&self, pane_id: &str, text: &str) -> Result<()> {
        let output = Command::new(&self.wezterm_path)
            .args(["cli", "send-text", "--pane-id", pane_id, "--no-paste", text])
            .output()
            .context("Failed to execute wezterm cli send-text")?;

        if !output.status.success() {
            return Err(anyhow!(
                "wezterm send-text command failed: {}",
                String::from_utf8_lossy(&output.stderr)
            ));
        }

        Ok(())
    }

    /// Activate a pane
    fn activate_pane(&self, pane_id: &str) -> Result<()> {
        let output = Command::new(&self.wezterm_path)
            .args(["cli", "activate-pane", "--pane-id", pane_id])
            .output()
            .context("Failed to execute wezterm cli activate-pane")?;

        if !output.status.success() {
            return Err(anyhow!(
                "wezterm activate-pane command failed: {}",
                String::from_utf8_lossy(&output.stderr)
            ));
        }

        Ok(())
    }

    /// Close a pane
    fn close_pane(&self, pane_id: &str) -> Result<()> {
        let output = Command::new(&self.wezterm_path)
            .args(["cli", "kill-pane", "--pane-id", pane_id])
            .output()
            .context("Failed to execute wezterm cli kill-pane")?;

        if !output.status.success() {
            return Err(anyhow!(
                "wezterm kill-pane command failed: {}",
                String::from_utf8_lossy(&output.stderr)
            ));
        }

        Ok(())
    }

    /// Get program running in a pane
    fn get_pane_program(&self, pane_id: &str) -> Result<String> {
        // Get all panes in JSON format
        let output = Command::new(&self.wezterm_path)
            .args(["cli", "list", "--format=json"])
            .output()
            .context("Failed to list panes with wezterm cli list")?;

        if !output.status.success() {
            return Err(anyhow!("wezterm cli list failed: {}", 
                String::from_utf8_lossy(&output.stderr)));
        }

        let output_str = String::from_utf8(output.stdout)
            .context("Failed to parse wezterm cli list output")?;
        
        // Parse the JSON
        let panes: Vec<WezTermPane> = serde_json::from_str(&output_str)
            .context("Failed to parse JSON output from wezterm cli list")?;
        
        // Find the pane with the matching ID
        let pane_id_num = pane_id.parse::<u64>()
            .context("Failed to parse pane ID as a number")?;
            
        for pane in &panes {
            if pane.pane_id == pane_id_num {
                return Ok(pane.title.clone());
            }
        }
        
        Err(anyhow!("Could not determine program for pane {}", pane_id))
    }
}

// This function has been replaced by Home Manager's xdg.configFile mechanism

/// Main function to handle the file picker integration
///
/// This function:
/// 1. Checks if a Yazi pane already exists and toggles it off if it does
/// 2. Creates a new pane in the specified direction and size
/// 3. Launches Yazi in the new pane with proper environment variables
/// 4. Passes the Helix pane ID to Yazi for file opening
///
/// # Arguments
///
/// * `wezterm_path` - Optional path to the WezTerm executable
/// * `yazi_path` - Optional path to the Yazi executable
/// * `yazi_config_dir` - Optional path to custom Yazi configuration
/// * `dir` - Optional directory to open Yazi in
/// * `width` - Width of the Yazi pane as a percentage
/// * `side` - Side to place the pane on ("left" or "right")
///
/// # Returns
///
/// * Success when Yazi is launched or toggled off
/// * Error if pane management or Yazi launch fails
fn open_picker(
    wezterm_path: Option<PathBuf>,
    yazi_path: Option<PathBuf>,
    yazi_config_dir: Option<PathBuf>,
    dir: Option<String>,
    width: u32,
    side: &str,
) -> Result<()> {
    // Initialize WezTerm client
    let wezterm = WezTermClient::new(wezterm_path)?;

    // Get Yazi path
    let yazi = match yazi_path {
        Some(path) => path.to_string_lossy().to_string(),
        None => which("yazi")
            .map(|p| p.to_string_lossy().to_string())
            .context("Yazi not found in PATH")?,
    };

    // Use the specified directory or current directory
    let current_dir = dir.unwrap_or_else(|| {
        std::env::current_dir()
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_else(|_| ".".to_string())
    });

    debug!("Using directory: {}", current_dir);

    // Setup pane for Yazi
    let direction = if side == "left" { "left" } else { "right" };

    // Get current pane ID for later reference
    let current_pane_id = wezterm.get_current_pane()?;
    debug!("Current pane ID: {}", current_pane_id);

    // Get panes in current tab
    let tab_panes = wezterm.get_panes_in_current_tab()?;
    debug!("Panes in current tab: {:?}", tab_panes);

    // Check if there's already a pane in the requested direction
    let existing_pane = wezterm.get_pane_by_direction(direction);

    // Check if the pane exists and is running Yazi
    let is_yazi_pane = match &existing_pane {
        Ok(pane_id) => {
            if tab_panes.contains(pane_id) {
                // Check if pane is running yazi
                let program = wezterm.get_pane_program(pane_id);
                if let Ok(prog) = program {
                    debug!("Program in existing pane: {}", prog);
                    prog.contains("yazi")
                } else {
                    false
                }
            } else {
                false
            }
        }
        Err(_) => false,
    };

    // If the pane exists and is running Yazi, toggle it off by closing it
    if is_yazi_pane {
        debug!("Yazi already running in {} pane, closing it", direction);
        
        // Close the Yazi pane
        if let Ok(pane_id) = &existing_pane {
            // First activate Helix pane to ensure focus returns there
            wezterm.activate_pane(&current_pane_id)?;
            
            // Then close the Yazi pane
            wezterm.close_pane(pane_id)?;
            info!("Closed Yazi pane");
        }
        return Ok(());
    }

    // Check if we need to reuse an existing pane or create a new one
    if let Ok(pane_id) = &existing_pane {
        if tab_panes.contains(pane_id) {
            // We have an existing pane in the right direction, but it's not running Yazi
            // Close it first to avoid leaving empty panes
            debug!("Closing existing non-Yazi pane before creating a new one");
            wezterm.close_pane(pane_id)?;
        }
    }

    // Prepare environment variables for Yazi
    let mut env_vars = vec![("HELIX_PANE_ID", current_pane_id.as_str())];
    
    // Add Yazi config dir if specified
    let config_home;
    if let Some(config_dir) = &yazi_config_dir {
        config_home = config_dir.to_string_lossy().to_string();
        env_vars.push(("YAZI_CONFIG_HOME", config_home.as_str()));
    }
    
    // Prepare Yazi command - we'll add directory as a separate argument
    let yazi_command = yazi;
    
    debug!("Creating new pane with Yazi command: {} and directory: {:?}", yazi_command, current_dir);
    debug!("Using environment variables: {:?}", env_vars);
    
    // Convert to &str for the command arguments
    let yazi_cmd_str = yazi_command.as_str();
    let current_dir_str = current_dir.as_str();
    
    // Add command and arguments separately to handle spaces properly
    let mut command_args = vec![yazi_cmd_str];
    if !current_dir.is_empty() {
        command_args.push(current_dir_str);
    }
    
    // Create a new pane and run Yazi with the directory as a separate argument
    let _yazi_pane_id = wezterm.split_pane_and_run_with_args(direction, width, &command_args, &env_vars)?;

    info!("Launched Yazi in {} pane", direction);

    Ok(())
}

/// Open a file in Helix without closing the Yazi pane
///
/// This function:
/// 1. Finds the Helix pane using environment variables or pane detection
/// 2. Activates the Helix pane
/// 3. Sends a command to open the specified file
/// 4. Returns to Yazi without closing it
///
/// # Arguments
///
/// * `wezterm_path` - Optional path to the WezTerm executable
/// * `file_path` - Path to the file to be opened in Helix
///
/// # Returns
///
/// * Success when the file is opened
/// * Error if Helix pane cannot be found or the file cannot be opened
fn open_file(wezterm_path: Option<PathBuf>, file_path: &str) -> Result<()> {
    // Initialize WezTerm client
    let wezterm = WezTermClient::new(wezterm_path)?;

    // Get the current pane ID - this is the Yazi pane
    let current_pane_id = wezterm.get_current_pane()?;
    debug!("Current (Yazi) pane ID: {}", current_pane_id);
    
    // Look for Helix pane ID in environment variable first (fastest and most reliable)
    let helix_pane_id = if let Ok(pane_id) = std::env::var("HELIX_PANE_ID") {
        debug!("Found Helix pane ID from environment: {}", pane_id);
        pane_id
    } else {
        // Fall back to searching for Helix pane
        debug!("Searching for Helix pane...");
        
        // Get panes in current tab
        let tab_panes = wezterm.get_panes_in_current_tab()?;
        debug!("Panes in current tab: {:?}", tab_panes);
        
        // Find the Helix pane in the current tab
        let mut helix_pane = None;
        
        // First try to find by direction (prefer right pane, then left)
        for direction in &["right", "left"] {
            if let Ok(pane_id) = wezterm.get_pane_by_direction(direction) {
                if tab_panes.contains(&pane_id) {
                    // Check if pane is running helix
                    let program = wezterm.get_pane_program(&pane_id);
                    if let Ok(prog) = program {
                        if prog.contains("hx") {
                            helix_pane = Some(pane_id.clone());
                            debug!("Found Helix pane in {} direction: {}", direction, pane_id);
                            break;
                        }
                    }
                }
            }
        }
        
        // If we couldn't find Helix in the expected panes, try all panes in the tab
        if helix_pane.is_none() {
            debug!("Searching all panes in tab for Helix");
            for pane_id in &tab_panes {
                let program = wezterm.get_pane_program(pane_id);
                if let Ok(prog) = program {
                    if prog.contains("hx") {
                        helix_pane = Some(pane_id.clone());
                        debug!("Found Helix pane: {}", pane_id);
                        break;
                    }
                }
            }
        }
        
        // Use Yazi pane as absolute fallback (though this will likely fail)
        helix_pane.unwrap_or_else(|| {
            debug!("Could not find a pane running Helix, using current pane as fallback");
            current_pane_id.clone()
        })
    };
    
    // 1. Activate the Helix pane
    wezterm.activate_pane(&helix_pane_id)?;
    
    // 2. Get absolute path of the file
    let file_path = Path::new(file_path);
    let abs_path = if file_path.is_absolute() {
        file_path.to_path_buf()
    } else {
        std::env::current_dir()?.join(file_path)
    };
    
    // 3. Send command to open the file
    let open_command = format!(":open {}\r", abs_path.display());
    wezterm.send_text_to_pane(&helix_pane_id, &open_command)?;
    
    info!("Opened file in Helix: {}. Yazi pane remains open", abs_path.display());
    
    // Return immediately without closing the Yazi pane
    Ok(())
}

// Install functionality has been moved to Home Manager's xdg.configFile mechanism

fn main() -> Result<()> {
    let cli = Cli::parse();

    // Setup logger
    env_logger::Builder::new()
        .filter_level(if cli.verbose {
            log::LevelFilter::Debug
        } else {
            log::LevelFilter::Info
        })
        .init();

    match &cli.command {
        Commands::OpenPicker { dir, width, side, wezterm_path, yazi_path, yazi_config_dir } => open_picker(
            // Prefer command-specific args over global ones
            wezterm_path.clone().or_else(|| cli.wezterm_path.clone()),
            yazi_path.clone().or_else(|| cli.yazi_path.clone()),
            yazi_config_dir.clone().or_else(|| cli.yazi_config_dir.clone()),
            dir.clone(),
            *width,
            side,
        ),
        Commands::OpenFile { path, wezterm_path } => open_file(
            wezterm_path.clone().or_else(|| cli.wezterm_path.clone()),
            path
        ),
    }
}
