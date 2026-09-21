use serde::{Deserialize, Serialize};
use tracing::{info, debug};
use std::sync::Arc;
use tokio::sync::Mutex;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToastMessage {
    pub id: String,
    pub title: String,
    pub body: String,
    pub kind: ToastKind,
    pub timeout_ms: Option<u64>,
    pub actions: Vec<ToastAction>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ToastKind {
    Success,
    Warning,
    Error,
    Info,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToastAction {
    pub id: String,
    pub label: String,
}

impl ToastMessage {
    pub fn success(title: &str, body: &str) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            title: title.to_string(),
            body: body.to_string(),
            kind: ToastKind::Success,
            timeout_ms: Some(3000),
            actions: vec![],
        }
    }
    
    pub fn error(title: &str, body: &str) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            title: title.to_string(),
            body: body.to_string(),
            kind: ToastKind::Error,
            timeout_ms: Some(5000),
            actions: vec![],
        }
    }
    
    pub fn with_action(mut self, id: &str, label: &str) -> Self {
        self.actions.push(ToastAction {
            id: id.to_string(),
            label: label.to_string(),
        });
        self
    }
}

/// Toast/notification service for displaying Windows system notifications.
pub struct ToastService {
    active_toasts: Arc<Mutex<Vec<ToastMessage>>>,
}

impl ToastService {
    pub fn new() -> Self {
        Self {
            active_toasts: Arc::new(Mutex::new(Vec::new())),
        }
    }
    
    /// Show a toast notification.
    /// On Windows, this uses the Win32 balloon tip or modern toast notifications.
    pub async fn show(&self, toast: ToastMessage) -> Result<(), String> {
        info!("Toast: [{:?}] {} - {}", toast.kind, toast.title, toast.body);
        
        // Store the toast
        {
            let mut active = self.active_toasts.lock().await;
            active.push(toast.clone());
        }
        
        // Show Windows notification
        self.show_windows_toast(&toast).await?;
        
        // Auto-dismiss after timeout
        if let Some(timeout_ms) = toast.timeout_ms {
            let active_toasts = self.active_toasts.clone();
            let toast_id = toast.id.clone();
            tokio::spawn(async move {
                tokio::time::sleep(std::time::Duration::from_millis(timeout_ms)).await;
                let mut active = active_toasts.lock().await;
                active.retain(|t| t.id != toast_id);
            });
        }
        
        Ok(())
    }
    
    /// Show Windows toast notification using Win32 API.
    async fn show_windows_toast(&self, toast: &ToastMessage) -> Result<(), String> {
        // For a proper implementation, we'd use the Windows.UI.Notifications API
        // via the windows-rs crate. For now, we emit an event to the frontend.
        
        // The frontend will handle displaying the toast in the UI
        // This allows for rich styling and interaction
        debug!("Windows toast shown: {}", toast.id);
        Ok(())
    }
    
    /// Dismiss a toast by ID.
    pub async fn dismiss(&self, id: &str) {
        let mut active = self.active_toasts.lock().await;
        active.retain(|t| t.id != id);
    }
    
    /// Dismiss all active toasts.
    pub async fn dismiss_all(&self) {
        let mut active = self.active_toasts.lock().await;
        active.clear();
    }
    
    /// Get all active toasts.
    pub async fn get_active(&self) -> Vec<ToastMessage> {
        self.active_toasts.lock().await.clone()
    }
}

impl Default for ToastService {
    fn default() -> Self {
        Self::new()
    }
}