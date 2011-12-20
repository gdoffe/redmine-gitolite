require_dependency 'app/models/repository/git'
module GitoliteRedmine
  module Patches
    module GitPatch
	module InstanceMethods
	  
          def branch_pattern=(arg)
            write_attribute(:branch_pattern, arg ? arg.to_s.strip : nil)
          end

          def tag_pattern=(arg)
            write_attribute(:tag_pattern, arg ? arg.to_s.strip : nil)
          end
        end
  
        def self.included(base)
          base.class_eval do
            unloadable
          end

	  base.send(:include, InstanceMethods)
        end
    end
  end
end

#require 'dispatcher'
#Dispatcher.to_prepare do
#  Issue.send(:include, GitoliteRedmine::Patches::GitPatch::InstanceMethods)
#end
Repository::Git.send(:include, GitoliteRedmine::Patches::GitPatch) unless Repository::Git.include?(GitoliteRedmine::Patches::GitPatch)
