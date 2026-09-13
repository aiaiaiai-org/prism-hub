# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class TelegramSurfaceBindingTest < Minitest::Test
  def test_root_surface_exposes_logical_context_and_reply_target
    binding = build_binding(chat_id: -1001234567890)

    assert_predicate binding, :active?
    assert_equal({"workspace" => "personal-a", "channel" => "digest"}, binding.logical_context)
    assert_equal "telegram:-1001234567890:root", binding.surface_scope
    assert_equal({chat_id: -1001234567890}, binding.reply_target)
    assert binding.frozen?
  end

  def test_topic_surface_preserves_message_thread_id
    binding = build_binding(chat_id: -1001234567890, message_thread_id: 42)

    assert_equal "telegram:-1001234567890:42", binding.surface_scope
    assert_equal({chat_id: -1001234567890, message_thread_id: 42}, binding.reply_target)
  end

  def test_rejects_zero_chat_id
    error = assert_raises(PrismHub::InputError) do
      build_binding(chat_id: 0)
    end

    assert_equal "hub.telegram_surface_binding.chat_id.invalid", error.code
  end

  def test_rejects_nonpositive_thread_id
    error = assert_raises(PrismHub::InputError) do
      build_binding(message_thread_id: 0)
    end

    assert_equal "hub.telegram_surface_binding.message_thread_id.invalid", error.code
  end

  def test_rejects_revoked_state_without_auditable_revoker
    error = assert_raises(PrismHub::InputError) do
      build_binding(
        status: "revoked",
        revoked_at: Time.utc(2026, 9, 13, 8, 0),
        revoked_by_user_identity_id: nil
      )
    end

    assert_equal "hub.telegram_surface_binding.state.invalid", error.code
  end

  def test_accepts_coherent_revoked_state
    revoked_at = Time.utc(2026, 9, 13, 8, 0)
    binding = build_binding(
      status: "revoked",
      revoked_at: revoked_at,
      revoked_by_user_identity_id: "user-b"
    )

    assert_predicate binding, :revoked?
    assert_equal revoked_at, binding.revoked_at
    assert_equal "user-b", binding.revoked_by_user_identity_id
  end

  private

  def build_binding(**overrides)
    PrismHub::Domain::TelegramSurfaceBinding.new(
      **{
        id: "binding-a",
        workspace_id: "personal-a",
        bot_instance_id: "bot-instance-a",
        logical_channel: "digest",
        chat_id: -1001234567890,
        message_thread_id: nil,
        created_by_user_identity_id: "user-a",
        status: "active",
        revoked_at: nil,
        revoked_by_user_identity_id: nil
      }.merge(overrides)
    )
  end
end
