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
          
          @repo.save_and_apply
          FileUtils.rm_rf local_dir
          unlock
        end
      end
    end
    
    def update_projects(projects)
      recursion_check do
        projects = (projects.is_a?(Array) ? projects : [projects])

        if projects.detect{|p| p.repositories.detect{|r| r.is_a?(Repository::Gitolite)}} && lock
          clone(Setting.plugin_redmine_gitolite['gitoliteUrl'], local_dir)
          
          projects.select{|p| p.repositories.detect{|r| r.is_a?(Repository::Gitolite)}}.each do |project|
            logger.debug "[Gitolite] Handling #{project.inspect}"
            handle_project project
          end

          @repo.save_and_apply
          #FileUtils.rm_rf local_dir
          unlock
        end
      end
    end

    def destroy_projects(projects)
      recursion_check do
        projects = (projects.is_a?(Array) ? projects : [projects])

        if projects.detect{|p| p.repositories.detect{|r| r.is_a?(Repository::Gitolite)}} && lock
          clone(Setting.plugin_redmine_gitolite['gitoliteUrl'], local_dir)

          projects.select{|p| p.repository.is_a?(Repository::Gitolite)}.each do |project|
            logger.debug "[Gitolite] Handling #{project.inspect}"
            destroy_project project
          end

          @repo.save_and_apply
          FileUtils.rm_rf local_dir
          unlock
        end
      end
    end

    def destroy_repositories(repositories)
      recursion_check do
        repositories = (repositories.is_a?(Array) ? repositories : [repositories])

        if repositories.detect{|r| r.is_a?(Repository::Gitolite)} && lock
          clone(Setting.plugin_redmine_gitolite['gitoliteUrl'], local_dir)

          repositories.select{|r| r.is_a?(Repository::Gitolite)}.each do |repository|
            logger.debug "[Gitolite] Handling #{repository.inspect}"
            destroy_repository repository
          end

          @repo.save_and_apply
          FileUtils.rm_rf local_dir
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
      @repo = Gitolite::GitoliteAdmin.new(local_dir, {  :git_user => Setting.plugin_redmine_gitolite['gitoliteUser'],
                                                        :host => Setting.plugin_redmine_gitolite['gitoliteHost'],
                                                        :public_key => File.expand_path(Setting.plugin_redmine_gitolite['gitolitePublicKey']),
                                                        :private_key => File.expand_path(Setting.plugin_redmine_gitolite['gitolitePrivateKey'])
                                                     })
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
      
      project.repositories.select{|r| r.is_a?(Repository::Gitolite)}.each do |repository|
        name = repository.identifier.to_s
        conf = @repo.config.repos[name]
        proj_ids = []

        unless conf
          conf = Gitolite::Config::Repo.new(name)
          @repo.config.add_repo(conf)
        end

        proj_ids = conf.config["hooks.redmine_gitolite.projectid"].split(' ') unless conf.config["hooks.redmine_gitolite.projectid"].nil?
        if proj_ids.index(proj_name).nil?
          proj_ids.append(proj_name)
        end
        conf.set_git_config("hooks.redmine_gitolite.projectid", proj_ids.join(' '))

        conf.set_git_config("hooks.redmine_gitolite.server", Setting.protocol + '://' + Setting.host_name.to_s)

        if repository.is_default?
          conf.permissions = build_permissions(users, project)
        end
      end
    end

    def destroy_project(project)
      users = project.member_principals.map(&:user).compact.uniq
      proj_name = project.identifier.to_s

      project.repositories.select{|r| r.is_a?(Repository::Gitolite)}.each do |repository|
        destroy_repository(repository)
      end
    end

    def destroy_repository(repository)
      name = repository.identifier.to_s
      conf = @repo.config.repos[name]
      proj_name = repository.project.identifier.to_s
      proj_ids = []

      proj_ids = conf.config["hooks.redmine_gitolite.projectid"].split(' ') unless conf.config["hooks.redmine_gitolite.projectid"].nil? 
      if !proj_ids.index(proj_name).nil?
        proj_ids.delete(proj_name)
      end
      conf.set_git_config("hooks.redmine_gitolite.projectid", proj_ids.join(' '))

      conf.set_git_config("hooks.redmine_gitolite.server", Setting.protocol + '://' + Setting.host_name.to_s)

      if repository.is_default?
        # Only gitolite admins will now have full access to that repository
        conf.permissions = @repo.config.get_repo("gitolite-admin").permissions
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
      read = []
      read << "redmine"
      #read << "daemon" if User.anonymous.allowed_to?(:view_changesets, project)
      #read << "gitweb" if User.anonymous.allowed_to?(:view_gitweb, project)
      full_access_users     = users.select{ |user| user.allowed_to?( :manage_repository, project ) }
      pattern_access_users  = users.select{ |user| user.allowed_to?( :commit_access, project ) } - full_access_users
      read_only_users       = users.select{ |user| user.allowed_to?( :browse_repository, project ) } - pattern_access_users

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
      
      if full_access_users
        user = full_access_users.map{|usr| usr.login.underscore}.sort
        permissions["RW"][""] += user unless user.empty?
        permissions["RW+"]["personal/USER/"] += user unless user.empty?
      end
      
      if pattern_access_users
        user = pattern_access_users.map{|usr| usr.login.underscore}.sort
        permissions["R"][""] += user unless user.empty?
        if project.repository.branch_pattern and project.repository.branch_pattern != ""
          permissions["RW"][project.repository.branch_pattern] += user unless user.empty?
        end
        if project.repository.tag_pattern and project.repository.tag_pattern != ""
          permissions["RW"]["ref/tags/" + project.repository.tag_pattern] += user unless user.empty?
        end
        permissions["RW+"]["personal/USER/"] += user unless user.empty?
      end
      
      if read_only_users
        user = read_only_users.map{|usr| usr.login.underscore}.sort
        permissions["R"][""] += user unless user.empty?
        permissions["RW+"]["personal/USER/"] += user unless user.empty?
      end

      if project.repository.branch_pattern and project.repository.branch_pattern != ""
        if permissions["RW"][project.repository.branch_pattern].empty?; permissions["RW"].delete(project.repository.branch_pattern); end
      end
      if project.repository.tag_pattern and project.repository.tag_pattern != ""
        if permissions["RW"]["ref/tags/" + project.repository.tag_pattern].empty?; permissions["RW"].delete("ref/tags/" + project.repository.tag_pattern); end
      end

      permissions["RW"][""] -= permissions["RW+"][""]
      permissions["R"][""]  -= permissions["RW"][""]
      permissions["R"][""]  -= permissions["RW+"][""]

      permissions["RW+"]["personal/USER/"] = permissions["RW+"]["personal/USER/"].uniq

      if permissions["R"][""].empty?; permissions["R"].delete(""); end
      if permissions["RW"][""].empty?; permissions["RW"].delete(""); end
      if permissions["RW+"][""].empty?; permissions["RW+"].delete(""); end
      if permissions["RW+"]["personal/USER/"].empty?; permissions["RW+"].delete("personal/USER/"); end

      if permissions["R"].empty?; permissions.delete("R"); end
      if permissions["RW"].empty?; permissions.delete("RW"); end
      if permissions["RW+"].empty?; permissions.delete("RW+"); end

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
