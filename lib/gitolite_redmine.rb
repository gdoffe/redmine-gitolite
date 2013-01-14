require 'lockfile'
require 'gitolite'
require 'fileutils'
require 'net/ssh'
require 'tmpdir'

module GitoliteRedmine
  class AdminHandler
    include Redmine::I18n
    @@recursionCheck = false
    
    def update_user(user)
      recursion_check do 
        if lock
          clone(Setting.plugin_redmine_gitolite['gitoliteUrl'], local_dir)
          
          logger.debug "[Gitolite] Handling #{user.inspect}"
          add_active_keys(user.gitolite_public_keys.active)
          remove_inactive_keys(user.gitolite_public_keys.inactive)
          
          @repo.save
          @repo.apply
          FileUtils.rm_rf local_dir
          unlock
        end
      end
    end
    
    def update_projects(projects)
      recursion_check do
        projects = (projects.is_a?(Array) ? projects : [projects])

        if projects.detect{|p| p.repositories.detect{|r| r.is_a?(Repository::Git)}} && lock
          clone(Setting.plugin_redmine_gitolite['gitoliteUrl'], local_dir)
          
          projects.select{|p| p.repository.is_a?(Repository::Git)}.each do |project|
            logger.debug "[Gitolite] Handling #{project.inspect}"
            handle_project project
          end

          @repo.save
          @repo.apply
          #FileUtils.rm_rf local_dir
          unlock
        end
      end
    end
    
    private
    
    def local_dir
      @local_dir ||= File.join(Rails.root,"tmp","redmine_gitolite_#{Time.now.to_i}")
    end
    
    def clone(origin, local_dir)
      FileUtils.mkdir_p local_dir
      result = `git clone #{origin} #{local_dir}`
      logger.debug result
      @repo = Gitolite::GitoliteAdmin.new local_dir
    end
    
    def lock
      lockfile_path = File.join(Rails.root,"tmp",'redmine_gitolite_lock')
      @lockfile = File.new(lockfile_path, File::CREAT|File::RDWR)
      retries = 5
      while (retries -= 1) > 0
        return @lockfile if @lockfile.flock(File::LOCK_EX|File::LOCK_NB)
        sleep 2
      end
      false
    end
    
    def unlock
      @lockfile.flock(File::LOCK_UN)
    end
    
    def handle_project(project)
      users = project.member_principals.map(&:user).compact.uniq
      proj_name = project.identifier.to_s
      
      project.repositories.select{|r| r.is_a?(Repository::Git)}.each do |repository|
        name = repository.identifier.to_s
        conf = @repo.config.repos[name]
      
        unless conf
          conf = Gitolite::Config::Repo.new(name)
          conf.set_git_config("hooks.redmine_gitolite.projectid", proj_name)
          @repo.config.add_repo(conf)
        end
      
        conf.permissions = build_permissions(users, project)
      end
    end
    
    def add_active_keys(keys) 
      keys.each do |key|
        parts = key.key.split
        repo_keys = @repo.ssh_keys[key.owner]
        repo_key = repo_keys.find_all{|k| k.location == key.location && k.owner == key.owner}.first
        if repo_key
          repo_key.type, repo_key.blob, repo_key.email = parts
          repo_key.owner = key.owner
        else
          repo_key = Gitolite::SSHKey.new(parts[0], parts[1], parts[2])
          repo_key.location = key.location
          repo_key.owner = key.owner
          @repo.add_key repo_key
        end
      end
    end
    
    def remove_inactive_keys(keys)
      keys.each do |key|
        repo_keys = @repo.ssh_keys[key.owner]
        repo_key = repo_keys.find_all{|k| k.location == key.location && k.owner == key.owner}.first
        @repo.rm_key repo_key if repo_key
      end
    end
    
    def build_permissions(users, project)
      read_users = users.select{|user| user.allowed_to?(:view_changesets, project) && !user.allowed_to?(:commit_access, project) }
      read = read_users.map{|usr| usr.login.underscore.gsub(/[^0-9a-zA-Z\-\_]/,'_')}.sort

      # Managers
      role = Role.find_by_name(l(:default_role_manager))
      logger.debug { "********* Role : #{role}" }
      manager_users = project.users_by_role[role]
      logger.debug { "********* Managers : #{manager_users}" }
      if manager_users
        manager_users = manager_users.select{ |user| user.allowed_to?( :commit_access, project ) }
      end
      
      # Developers
      role = Role.find_by_name(l(:default_role_developer))
      developer_users = project.users_by_role[role]
      if developer_users
        developer_users = developer_users.select{ |user| user.allowed_to?( :commit_access, project ) }
      end
      
      # Reporters
      role = Role.find_by_name(l(:default_role_reporter))
      reporter_users = project.users_by_role[role]
      if reporter_users
        reporter_users = reporter_users.select{ |user| user.allowed_to?( :view_changesets, project ) }
      end
      
      read << "redmine"
      read << "daemon" if User.anonymous.allowed_to?(:view_changesets, project)
      read << "gitweb" if User.anonymous.allowed_to?(:view_gitweb, project)
      
      permissions = {}

      permissions["R"] = {}
      permissions["RW"] = {}
      permissions["RW+"] = {}
      
      permissions["R"][""] = []
      
      permissions["RW"][""] = []
      if project.repository.branch_pattern and project.repository.branch_pattern != ""
          permissions["RW"][project.repository.branch_pattern] = []
      end
      if project.repository.tag_pattern and project.repository.tag_pattern != ""
          permissions["RW"]["ref/tags/" + project.repository.tag_pattern] = []
      end
      
      permissions["RW+"][""] = []
      permissions["RW+"]["personal/USER/"] = []
      
      permissions["R"][""] += read unless read.empty?
      
      if manager_users
        manager = manager_users.map{|usr| usr.login.underscore}.sort
        permissions["RW"][""] += manager unless manager.empty?
        permissions["RW+"]["personal/USER/"] += manager unless manager.empty?
      end
      
      if developer_users
        developer = developer_users.map{|usr| usr.login.underscore}.sort
        permissions["R"][""] += developer unless developer.empty?
        if project.repository.branch_pattern and project.repository.branch_pattern != ""
          permissions["RW"][project.repository.branch_pattern] += developer unless developer.empty?
        end
        if project.repository.tag_pattern and project.repository.tag_pattern != ""
          permissions["RW"]["ref/tags/" + project.repository.tag_pattern] += developer unless developer.empty?
        end
        permissions["RW+"]["personal/USER/"] += developer unless developer.empty?
      end
      
      if reporter_users
        reporter = reporter_users.map{|usr| usr.login.underscore}.sort
        permissions["R"][""] += reporter unless reporter.empty?
        if project.repository.branch_pattern and project.repository.branch_pattern != ""
          permissions["RW"][project.repository.branch_pattern] += reporter unless reporter.empty?
        end
        if project.repository.tag_pattern and project.repository.tag_pattern != ""
          permissions["RW"]["ref/tags/" + project.repository.tag_pattern] += reporter unless reporter.empty?
        end
        permissions["RW+"]["personal/USER/"] += reporter unless reporter.empty?
      end

      if project.repository.branch_pattern and project.repository.branch_pattern != ""
        if permissions["RW"][project.repository.branch_pattern].empty?; permissions["RW"].delete(project.repository.branch_pattern); end
      end
      if project.repository.tag_pattern and project.repository.tag_pattern != ""
        if permissions["RW"]["ref/tags/" + project.repository.tag_pattern].empty?; permissions["RW"].delete("ref/tags/" + project.repository.tag_pattern); end
      end
      
      
      if permissions["R"][""].empty?; permissions["R"].delete(""); end
      if permissions["RW"][""].empty?; permissions["RW"].delete(""); end
      if permissions["RW+"][""].empty?; permissions["RW+"].delete(""); end
      if permissions["RW+"]["personal/USER/"].empty?; permissions["RW+"].delete("personal/USER/"); end

      [permissions]
    end
    
    def recursion_check
      return if @@recursionCheck
      begin
        @@recursionCheck = true
        yield
      rescue Exception => e
        logger.error "#{e.inspect} #{e.backtrace}"
      ensure
        @@recursionCheck = false
      end
    end
    
    def logger
      Rails.logger
    end
  end
end
