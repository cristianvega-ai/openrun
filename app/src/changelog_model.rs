use std::collections::HashMap;
use std::fmt;
use std::sync::Arc;

use channel_versions::Changelog;
use markdown_parser::FormattedText;
use warpui::assets::asset_cache::AssetSource;
use warpui::{Entity, ModelContext, SingletonEntity};

use crate::server::server_api::ServerApi;

pub struct ChangelogModel {
    pub changelog: ChangelogState,
    pub parsed_changelog: HashMap<String, FormattedText>,
    pub oz_updates: Vec<FormattedText>,
    pub server_api: Arc<ServerApi>,
    pub image: Option<AssetSource>,
}

impl ChangelogModel {
    pub fn new(server_api: Arc<ServerApi>) -> Self {
        Self {
            changelog: ChangelogState::None,
            parsed_changelog: HashMap::new(),
            oz_updates: Vec::new(),
            server_api,
            image: None,
        }
    }

    pub fn check_for_changelog(
        &mut self,
        request_type: ChangelogRequestType,
        ctx: &mut ModelContext<Self>,
    ) {
        match &self.changelog {
            ChangelogState::Some(changelog) => {
                // Don't refetch the changelog if we already have it
                ctx.notify();
                ctx.emit(Event::ChangelogRequestComplete {
                    request_type,
                    changelog: changelog.clone(),
                });
            }
            ChangelogState::Pending => {
                // There is already a request pending, so no-op while we wait for the response
            }
            ChangelogState::None => {
                log::info!("No changelog found for current version and channel");
                ctx.emit(Event::ChangelogRequestFailed { request_type });
            }
        }
    }

    pub fn is_check_pending(&self) -> bool {
        matches!(self.changelog, ChangelogState::Pending)
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum ChangelogHeader {
    NewFeatures,
    Improvements,
    BugFixes,
}

impl fmt::Display for ChangelogHeader {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            ChangelogHeader::NewFeatures => write!(f, "New features"),
            ChangelogHeader::Improvements => write!(f, "Improvements"),
            ChangelogHeader::BugFixes => write!(f, "Bug fixes"),
        }
    }
}

#[derive(Debug)]
pub enum Event {
    ChangelogRequestComplete {
        request_type: ChangelogRequestType,
        changelog: Changelog,
    },
    ChangelogRequestFailed {
        request_type: ChangelogRequestType,
    },
    ImageRequestComplete,
}

#[derive(Debug)]
pub enum ChangelogRequestType {
    WindowLaunch,
    UserAction,
}

pub enum ChangelogState {
    None,
    Pending,
    Some(Changelog),
}

impl Entity for ChangelogModel {
    type Event = Event;
}

impl SingletonEntity for ChangelogModel {}
