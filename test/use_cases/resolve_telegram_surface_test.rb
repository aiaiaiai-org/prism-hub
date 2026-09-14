# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

require_relative "../test_helper"

class ResolveTelegramSurfaceTest < Minitest::Test
  def test_returns_active_binding
    binding = Object.new
    repository = Object.new
    repository.define_singleton_method(:find_by_logical_context) { |workspace_id:, logical_channel:| binding }

    result = PrismHub::UseCases::ResolveTelegramSurface.new(binding_repository: repository).call(
      workspace_id: "workspace-1",
      logical_channel: "digest"
    )

    assert_same binding, result
  end

  def test_fails_closed_when_no_binding_exists
    repository = Object.new
    repository.define_singleton_method(:find_by_logical_context) { |**| nil }

    error = assert_raises(PrismHub::TelegramSurfaceBindingNotFoundError) do
      PrismHub::UseCases::ResolveTelegramSurface.new(binding_repository: repository).call(
        workspace_id: "workspace-1",
        logical_channel: "digest"
      )
    end

    assert_equal "hub.telegram_surface_binding.not_found", error.code
  end
end
