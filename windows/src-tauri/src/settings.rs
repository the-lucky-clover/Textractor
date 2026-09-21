use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AppSettings {
    pub weirdness: f64,
    pub custom_vocabulary: Vec<String>,
    pub ui_language: String,
    pub paste_as_plain_text: bool,
    pub flatten_text: bool,
    pub window_capture_as_table: bool,
    pub pii_redaction_enabled: bool,
    pub history_entry_limit: usize,
    pub menubar_color_icon: bool,
    pub knowledge_mode_enabled: bool,
    pub extended_logging_enabled: bool,
    pub show_confidence_badge: bool,
    pub clipboard_image_ocr: bool,
    pub structured_export_enabled: bool,
    pub auto_paste: bool,
    pub reduce_motion: bool,
}

impl AppSettings {
    pub fn new() -> Self {
        Self {
            weirdness: 0.45,
            custom_vocabulary: vec![],
            ui_language: String::new(),
            paste_as_plain_text: true,
            flatten_text: false,
            window_capture_as_table: true,
            pii_redaction_enabled: true,
            history_entry_limit: 200,
            menubar_color_icon: true,
            knowledge_mode_enabled: false,
            extended_logging_enabled: false,
            show_confidence_badge: true,
            clipboard_image_ocr: false,
            structured_export_enabled: true,
            auto_paste: true,
            reduce_motion: false,
        }
    }

    pub fn load() -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let path = Self::settings_path();
        if path.exists() {
            let data = fs::read_to_string(&path)?;
            let settings: Self = serde_json::from_str(&data)?;
            info!("Loaded settings from {}", path.display());
            Ok(settings)
        } else {
            Ok(Self::new())
        }
    }

    pub fn save(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let path = Self::settings_path();
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let json = serde_json::to_string_pretty(self)?;
        fs::write(&path, json)?;
        info!("Saved settings to {}", path.display());
        Ok(())
    }

    pub fn settings_path() -> PathBuf {
        let base = std::env::var("APPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("./"))
            .join("Textractor");
        base.join("settings.json")
    }
}