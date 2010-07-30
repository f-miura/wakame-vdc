require 'sequel'

module Dcmgr
  module Models
    class Log < Sequel::Model
      many_to_one :account
      many_to_one :user, :left_primary_key=>:user_id

      def before_create
        super
        self.created_at = Time.now unless self.created_at
      end

      def validate
        errors.add(:account, "can't empty") unless (self.account or self.account_id)
        errors.add(:tareget_uuid, "can't empty") unless self.target_uuid
        errors.add(:action, "can't empty") unless self.action
        errors.add(:user, "can't empty") unless (self.user or self.user_id)

        errors.add(:action, "mismatch action") unless /^(\S+)$/ =~ self.action
      end
    end
  end
end