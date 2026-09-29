use warpui::{SingletonEntity, UpdateView};

use super::{
    AIAgentExchangeId, AIConversationId, AppContext, BlocklistAIHistoryModel, CONTEXT_MENU_WIDTH,
    ChannelState, ClipboardContent, ContextMenuAction, ContextMenuState, ContextMenuType, EntityId,
    MenuItem, MenuItemFields, RichContentLink, ServerConversationToken, ServerOutputId,
    TerminalAction, TerminalModel, TerminalView, Tip, TipHint, ViewContext,
    mark_feature_used_and_write_to_user_defaults,
};

impl TerminalView {
    pub(super) fn ai_block_copying_menu_items(
        &self,
        ai_block_view_id: EntityId,
        hovered_link: Option<RichContentLink>,
        model: &TerminalModel,
        ctx: &mut ViewContext<Self>,
    ) -> Vec<MenuItem<TerminalAction>> {
        let mut items = vec![
            MenuItemFields::new("Copy")
                .with_on_select_action(TerminalAction::ContextMenu(
                    ContextMenuAction::CopyAIBlock { ai_block_view_id },
                ))
                .into_item(),
            MenuItemFields::new("Copy prompt")
                .with_on_select_action(TerminalAction::ContextMenu(
                    ContextMenuAction::CopyAIBlockQuery { ai_block_view_id },
                ))
                .into_item(),
            MenuItemFields::new("Copy output as Markdown")
                .with_on_select_action(TerminalAction::ContextMenu(
                    ContextMenuAction::CopyAIBlockOutput { ai_block_view_id },
                ))
                .into_item(),
        ];

        if let Some(link) = hovered_link {
            match link {
                RichContentLink::Url(url) => {
                    items.push(
                        MenuItemFields::new("Copy URL")
                            .with_on_select_action(TerminalAction::ContextMenu(
                                ContextMenuAction::CopyUrl { url_content: url },
                            ))
                            .into_item(),
                    );
                }
                #[cfg(feature = "local_fs")]
                RichContentLink::FilePath { absolute_path, .. } => {
                    items.push(
                        MenuItemFields::new("Copy path")
                            .with_on_select_action(TerminalAction::ContextMenu(
                                ContextMenuAction::CopyUrl {
                                    url_content: absolute_path.to_string_lossy().into_owned(),
                                },
                            ))
                            .into_item(),
                    );
                }
            }
        }

        let num_requested_commands = self
            .rich_content_views
            .iter()
            .find_map(|rich_content| {
                let ai_metadata = rich_content.ai_block_metadata()?;
                if ai_metadata.ai_block_handle.id() == ai_block_view_id {
                    return Some(ai_metadata.ai_block_handle.as_ref(ctx));
                }
                None
            })
            .map_or_else(|| 0, |ai_block| ai_block.num_requested_commands());

        if num_requested_commands > 0 {
            items.push(
                MenuItemFields::new(String::from("Copy command"))
                    .with_on_select_action(TerminalAction::ContextMenu(
                        ContextMenuAction::CopyAgentCommand { ai_block_view_id },
                    ))
                    .into_item(),
            );
        }

        let action_ids: Vec<_> = self
            .rich_content_views
            .iter()
            .find_map(|rich_content| {
                let ai_metadata = rich_content.ai_block_metadata()?;
                if ai_metadata.ai_block_handle.id() == ai_block_view_id {
                    return Some(ai_metadata.ai_block_handle.as_ref(ctx));
                }
                None
            })
            .map(|ai_block| {
                ai_block
                    .requested_commands_iter()
                    .map(|(action_id, _)| action_id)
                    .collect()
            })
            .unwrap_or_default();

        let has_git_branch = action_ids.iter().any(|action_id| {
            model
                .block_list()
                .block_for_ai_action_id(action_id)
                .is_some_and(|block| block.git_branch().is_some())
        });
        if has_git_branch {
            items.push(
                MenuItemFields::new(String::from("Copy git branch"))
                    .with_on_select_action(TerminalAction::ContextMenu(
                        ContextMenuAction::CopyAgentGitBranch { ai_block_view_id },
                    ))
                    .into_item(),
            );
        }
        let has_query_timestamp = self.rich_content_views.iter().any(|rich_content| {
            rich_content
                .ai_block_metadata()
                .filter(|metadata| metadata.ai_block_handle.id() == ai_block_view_id)
                .is_some_and(|metadata| {
                    metadata
                        .ai_block_handle
                        .as_ref(ctx)
                        .query_sent_at(ctx)
                        .is_some()
                })
        });
        if has_query_timestamp {
            items.push(
                MenuItemFields::new("Copy timestamp")
                    .with_on_select_action(TerminalAction::ContextMenu(
                        ContextMenuAction::CopyAIBlockTimestamp { ai_block_view_id },
                    ))
                    .into_item(),
            );
        }
        items.push(MenuItem::Separator);

        items.push(
            MenuItemFields::new("Copy conversation text")
                .with_on_select_action(TerminalAction::ContextMenu(
                    ContextMenuAction::CopyAIBlockConversation { ai_block_view_id },
                ))
                .into_item(),
        );

        items
    }

    fn conversation_text(
        &self,
        conversation_id: AIConversationId,
        ctx: &AppContext,
    ) -> Option<String> {
        let Some(conversation) =
            BlocklistAIHistoryModel::as_ref(ctx).conversation(&conversation_id)
        else {
            log::warn!("No conversation found for conversation ID {conversation_id}");
            return None;
        };

        let mut result = Vec::new();
        for exchange in conversation.root_task_exchanges() {
            let formatted_exchange =
                exchange.format_for_copy(Some(self.ai_action_model.as_ref(ctx)));
            if !formatted_exchange.is_empty() {
                result.push(formatted_exchange);
            }
        }

        if result.is_empty() {
            log::warn!("No copyable conversation text found for conversation ID {conversation_id}");
            return None;
        }

        Some(result.join("\n\n"))
    }

    pub(super) fn copy_conversation_text(
        &self,
        conversation_id: AIConversationId,
        ctx: &mut ViewContext<Self>,
    ) {
        if let Some(conversation_text) = self.conversation_text(conversation_id, ctx) {
            ctx.clipboard()
                .write(ClipboardContent::plain_text(conversation_text));
        }
    }

    fn copy_debugging_menu_items(
        &self,
        conversation_token: ServerConversationToken,
        server_output_id: Option<ServerOutputId>,
    ) -> Vec<(String, ContextMenuAction)> {
        if ChannelState::channel().is_dogfood() {
            vec![
                (
                    "Copy debugging link".to_string(),
                    ContextMenuAction::CopyAIDebuggingLink {
                        conversation_token: conversation_token.clone(),
                        request_id: server_output_id,
                    },
                ),
                (
                    "Copy conversation ID".to_string(),
                    ContextMenuAction::CopyConversationId {
                        conversation_id: conversation_token,
                    },
                ),
            ]
        } else {
            vec![(
                "Copy debugging ID".to_string(),
                ContextMenuAction::CopyExternalDebuggingId {
                    request_id: server_output_id,
                    conversation_id: conversation_token,
                },
            )]
        }
    }

    pub(super) fn create_copy_debugging_menu_item(
        &self,
        ai_exchange_id: AIAgentExchangeId,
        ai_conversation_id: AIConversationId,
        ctx: &mut ViewContext<Self>,
    ) -> Vec<(String, ContextMenuAction)> {
        let conversation_token = BlocklistAIHistoryModel::as_ref(ctx)
            .conversation(&ai_conversation_id)
            .and_then(|conversation| conversation.debugging_server_conversation_token());

        let Some(conversation_token) = conversation_token else {
            return Vec::new();
        };

        let server_output_id = self
            .ai_block_for_exchange(&ai_exchange_id)
            .and_then(|ai_block_handle| ai_block_handle.as_ref(ctx).server_output_id(ctx));
        self.copy_debugging_menu_items(conversation_token.clone(), server_output_id)
    }

    pub(super) fn open_ai_block_overflow_context_menu(
        &mut self,
        ai_block_view_id: EntityId,
        ai_exchange_id: AIAgentExchangeId,
        ai_conversation_id: AIConversationId,
        ctx: &mut ViewContext<Self>,
    ) {
        let mut menu_items = {
            let model = self.model.lock();
            self.ai_block_copying_menu_items(ai_block_view_id, None, &model, ctx)
        };

        let debugging_items =
            self.create_copy_debugging_menu_item(ai_exchange_id, ai_conversation_id, ctx);
        if !debugging_items.is_empty() {
            if !menu_items.is_empty() {
                menu_items.push(MenuItem::Separator);
            }
            for (button_text, action) in debugging_items {
                menu_items.push(
                    MenuItemFields::new(button_text)
                        .with_on_select_action(TerminalAction::ContextMenu(action))
                        .into_item(),
                );
            }
        }

        self.show_context_menu(
            ContextMenuState {
                menu_type: ContextMenuType::AIBlockOverflowMenu { ai_block_view_id },
            },
            menu_items,
            ctx,
        );
    }

    pub(super) fn show_context_menu(
        &mut self,
        menu_state: ContextMenuState,
        items: Vec<MenuItem<TerminalAction>>,
        ctx: &mut ViewContext<Self>,
    ) {
        ctx.update_view(&self.context_menu, |context_menu, view_ctx| {
            context_menu.set_origin(menu_state.menu_type.origin());
            context_menu.set_width(CONTEXT_MENU_WIDTH);
            // This will also reset the selection.
            context_menu.set_items(items, view_ctx);
        });

        self.context_menu_state = Some(menu_state);
        ctx.focus(&self.context_menu);
        ctx.notify();

        self.tips_completed.update(ctx, |tips, ctx| {
            mark_feature_used_and_write_to_user_defaults(
                Tip::Hint(TipHint::BlockAction),
                tips,
                ctx,
            );
            ctx.notify();
        });
    }
}
