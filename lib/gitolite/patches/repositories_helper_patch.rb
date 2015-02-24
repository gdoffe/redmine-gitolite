require_dependency 'repositories_helper'

module GitoliteRedmine
  module Patches
    module RepositoriesHelperPatch
      def self.included(base)
        base.send(:include, InstanceMethods)
        base.class_eval do
          unloadable

          # Must create an alias for the method to be created
          alias :gitolite_field_tags :gitolite_field_tags
        end
      end

      module InstanceMethods
        def gitolite_field_tags(form, repository)
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
      end
    end
  end
end

RepositoriesHelper.send(:include, GitoliteRedmine::Patches::RepositoriesHelperPatch) unless RepositoriesHelper.include?(GitoliteRedmine::Patches::RepositoriesHelperPatch)
