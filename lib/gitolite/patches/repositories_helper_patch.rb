require_dependency 'repositories_helper'
module GitoliteRedmine
  module Patches
    module RepositoriesHelperPatch
      def git_field_tags_with_disabled_configuration(form, repository)
    	content_tag('p', form.text_field(
                       :branch_pattern, :label => l(:field_gitolite_repository_branch_pattern),
                       :size => 60, :required => false,
                       :disabled => false
                         ) + l(:note_gitolite_repository_branch_pattern)) +
    	content_tag('p', form.text_field(
                       :tag_pattern, :label => l(:field_gitolite_repository_tag_pattern),
                       :size => 60, :required => false,
                       :disabled => false
                         ) + l(:note_gitolite_repository_tag_pattern))
      end
      
      def self.included(base)
        base.class_eval do
          unloadable
        end
        base.send(:alias_method_chain, :git_field_tags, :disabled_configuration)
      end
      
    end
  end
end
RepositoriesHelper.send(:include, GitoliteRedmine::Patches::RepositoriesHelperPatch) unless RepositoriesHelper.include?(GitoliteRedmine::Patches::RepositoriesHelperPatch)
