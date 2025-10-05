# frozen_string_literal: true

module Devagent
  # Plugin defines the optional API surface for auto-loaded extensions.
  module Plugin
    class << self
      def applies?(_repo_path)
        false
      end

      def priority
        0
      end

      def on_load(_ctx); end

      def on_index(_ctx); end

      def on_prompt(_ctx, _task)
        ""
      end

      def on_action(_ctx, _name, _args = {})
        nil
      end

      def on_post_edit(_ctx, _log); end

      def commands
        {}
      end

      def test_command(_ctx)
        nil
      end
    end
  end
end
