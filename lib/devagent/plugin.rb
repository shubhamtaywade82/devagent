# frozen_string_literal: true
module Devagent
  module Plugin
    def self.applies?(_repo_path); false end
    def self.priority; 0 end
    def self.on_load(_ctx); end
    def self.on_index(_ctx); end
    def self.on_prompt(_ctx, _task); "" end
    def self.on_action(_ctx, _name, _args = {}); nil end
    def self.on_post_edit(_ctx, _log); end
    def self.commands; {} end
  end
end
