use tauri::{Manager, RunEvent};
use std::sync::Arc;

mod settings;
mod history;
mod clipboard;
mod ocr;
mod toast;

#[tauri::command]
async fn get_settings() -> Result<settings::AppSettings, String> {
    settings::AppSettings::load().map_err(|e| e.to_string())
}

#[tauri::command]
async fn update_settings(new_settings: settings::AppSettings) -> Result<(), String> {
    new_settings.save().map_err(|e| e.to_string())
}

#[tauri::command]
async fn get_history() -> Result<Vec<history::CaptureRecord>, String> {
    history::HistoryStore::get_recent(50).map_err(|e| e.to_string())
}

#[tauri::command]
async fn export_history(format: String) -> Result<String, String> {
    match format.to_lowercase().as_str() {
        "json" => history::HistoryStore::export_json().map_err(|e| e.to_string()),
        "csv" => history::HistoryStore::export_csv().map_err(|e| e.to_string()),
        "markdown" | "md" => history::HistoryStore::export_markdown().map_err(|e| e.to_string()),
        _ => Err(format!("Unknown export format: {}", format))
    }
}

#[tauri::command]
async fn delete_capture(id: String) -> Result<(), String> {
    history::HistoryStore::delete(&id).map_err(|e| e.to_string())
}

#[tauri::command]
async fn clear_history() -> Result<(), String> {
    history::HistoryStore::clear().map_err(|e| e.to_string())
}

#[tauri::command]
async fn trigger_capture() -> Result<String, String> {
    // Capture trigger - full implementation on Windows via ScreenCapture API
    Ok("capture_triggered".to_string())
}

#[tauri::command]
async fn copy_text(text: String) -> Result<(), String> {
    Ok(()) // Clipboard write handled on frontend
}

#[tauri::command]
async fn show_toast(title: String, body: String, kind: String) -> Result<(), String> {
    eprintln!("[Toast {}] {} - {}", kind, title, body);
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            info!("Textractor Windows starting...");
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_settings,
            update_settings,
            get_history,
            export_history,
            delete_capture,
            clear_history,
            trigger_capture,
            copy_text,
            show_toast
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
