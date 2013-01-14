require_dependency 'repository/git'

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

#ActionDispatch::Callbacks.to_prepare do 
#  mon_fichier = File.open("/tmp/test.txt", "w")
#  mon_fichier.write "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\n"
#  mon_fichier.close
#  Issue.send(:include, GitoliteRedmine::Patches::GitPatch::InstanceMethods)
Repository::Git.safe_attributes 'branch_pattern'
Repository::Git.safe_attributes 'tag_pattern'
Repository::Git.send(:include, GitoliteRedmine::Patches::GitPatch) unless Repository::Git.include?(GitoliteRedmine::Patches::GitPatch)
