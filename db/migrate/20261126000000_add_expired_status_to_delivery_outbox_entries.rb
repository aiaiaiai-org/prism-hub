# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

# A queued notification that waited longer than its useful life is retired unsent: status `expired`.
class AddExpiredStatusToDeliveryOutboxEntries < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :delivery_outbox_entries, name: "delivery_outbox_entries_status_check"
    add_check_constraint :delivery_outbox_entries,
      "status IN ('pending', 'processing', 'delivered', 'failed', 'expired')",
      name: "delivery_outbox_entries_status_check"
  end

  def down
    # The older constraint does not know `expired`; those entries were never delivered, so they read as failed.
    execute "UPDATE delivery_outbox_entries SET status = 'failed' WHERE status = 'expired'"
    remove_check_constraint :delivery_outbox_entries, name: "delivery_outbox_entries_status_check"
    add_check_constraint :delivery_outbox_entries,
      "status IN ('pending', 'processing', 'delivered', 'failed')",
      name: "delivery_outbox_entries_status_check"
  end
end
