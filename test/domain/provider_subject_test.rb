# © 2026 aiaiaiai · aiaiaiai.org

require_relative "../test_helper"

class ProviderSubjectTest < Minitest::Test
  def test_provider_subject_is_scope_aware_and_immutable
    subject = PrismHub::Domain::ProviderSubject.new(
      provider: "meta.instagram",
      provider_scope: "app:123",
      subject_id: "opaque-provider-subject"
    )

    assert_equal "meta.instagram", subject.provider
    assert_equal "app:123", subject.provider_scope
    assert_equal "opaque-provider-subject", subject.subject_id
    assert_predicate subject, :frozen?
  end

  def test_same_subject_id_in_different_scope_is_not_the_same_provider_subject
    global = subject(scope: "global")
    application = subject(scope: "app:123")

    refute_equal global, application
  end

  def test_inspect_redacts_external_subject_id
    provider_subject = subject(scope: "global", subject_id: "123456789")

    refute_includes provider_subject.inspect, "123456789"
    assert_includes provider_subject.inspect, "subject_id=[redacted]"
  end

  def test_control_characters_are_rejected_from_opaque_subject_ids
    error = assert_raises(PrismHub::InputError) do
      subject(scope: "global", subject_id: "123\n456")
    end

    assert_equal "hub.provider_subject.subject_id.invalid", error.code
  end

  private

  def subject(scope:, subject_id: "same-subject")
    PrismHub::Domain::ProviderSubject.new(
      provider: "telegram",
      provider_scope: scope,
      subject_id: subject_id
    )
  end
end
