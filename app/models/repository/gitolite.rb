require 'redmine/scm/adapters/gitolite_adapter.rb'

class Repository::Gitolite < Repository::Git
  safe_attributes 'branch_pattern',
    'tag_pattern'

  def self.scm_adapter_class
    Redmine::Scm::Adapters::GitoliteAdapter
  end

  def self.scm_name
    'Gitolite'
  end

  def branch_pattern=(arg)
    write_attribute(:branch_pattern, arg ? arg.to_s.strip : nil)
  end

  def tag_pattern=(arg)
    write_attribute(:tag_pattern, arg ? arg.to_s.strip : nil)
  end
end

