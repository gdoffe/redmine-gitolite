require 'lockfile'
require 'gitolite'
require 'net/ssh'
require 'tmpdir'

module GitoliteRedmine
	include Redmine::I18n

	def self.update_repositories(projects)
		projects = (projects.is_a?(Array) ? projects : [projects])
	
		if(defined?(@recursionCheck))
			if(@recursionCheck)
				return
			end
		end
		@recursionCheck = true

		# Don't bother doing anything if none of the projects we've been handed have a Git repository
		unless projects.detect{|p|  p.repository.is_a?(Repository::Git)}.nil?

			lockfile=File.new(File.join(RAILS_ROOT,"tmp",'redmine_gitolite_lock'),File::CREAT|File::RDONLY)
			retries=5
			loop do
				break if lockfile.flock(File::LOCK_EX|File::LOCK_NB)
				retries-=1
				sleep 2
				raise Lockfile::MaxTriesLockError if retries<=0
			end


			# HANDLE GIT

			# create tmp dir
			local_dir = File.join(RAILS_ROOT,"tmp","redmine_gitolite_#{Time.now.to_i}")

			Dir.mkdir local_dir

			# clone repo
			`git clone #{Setting.plugin_redmine_gitolite['gitoliteUrl']} #{local_dir}/repo`
      
      ga_repo = Gitolite::GitoliteAdmin.new "#{local_dir}/repo"

			projects.select{|p| p.repository.is_a?(Repository::Git)}.each do |project|
				# fetch users
				users = project.member_principals.map(&:user).compact.uniq
				read_users = users.select{ |user| user.allowed_to?( :view_changesets, project ) && !user.allowed_to?( :commit_access, project ) }

				# Managers
                                role = Role.find(:first, :conditions => {:name => l(:default_role_manager)})
				manager_users = project.users_by_role[role]
				if manager_users
				  manager_users = manager_users.select{ |user| user.allowed_to?( :commit_access, project ) }
				end

				# Developers
                                role = Role.find(:first, :conditions => {:name => l(:default_role_developer)})
				developer_users = project.users_by_role[role]
				if developer_users
				  developer_users = developer_users.select{ |user| user.allowed_to?( :commit_access, project ) }
				end

				# Reporters
                                role = Role.find(:first, :conditions => {:name => l(:default_role_reporter)})
				reporter_users = project.users_by_role[role]
				if reporter_users
				  reporter_users = reporter_users.select{ |user| user.allowed_to?( :view_changesets, project ) }
				end

				# write key files
				users.map{|u| u.gitolite_public_keys.active}.flatten.compact.uniq.each do |key|
          parts = key.key.split
          k = ga_repo.ssh_keys[key.user.login.underscore].find_all{|k|k.location == key.title.underscore && k.owner == key.user.login.underscore}.first
          if k
            k.type = parts[0]
            k.blob = parts[1]
            k.email = parts[2]
            k.owner = key.user.login.underscore
          else
            k = Gitolite::SSHKey.new(parts[0], parts[1], parts[2])
            k.location = key.title.underscore
            k.owner = key.user.login.underscore
            ga_repo.add_key k
          end
				end

				# delete inactives
				users.map{|u| u.gitolite_public_keys.inactive}.flatten.compact.uniq.each do |key|
          k = ga_repo.ssh_keys[key.user.login.underscore].find_all{|k|k.location == key.title.underscore && k.owner == key.user.login.underscore}.first
					ga_repo.rm_key k if k
				end
      
				# write config file
        name = "#{project.identifier}"
				conf = ga_repo.config.repos[name]
        unless conf
          conf = Gitolite::Config::Repo.new(name)
          ga_repo.config.add_repo(conf)
        end
        
        read = read_users.map{|usr| usr.login.underscore}.sort
        read << "daemon" if User.anonymous.allowed_to?(:view_changesets, project)
        read << "gitweb" if User.anonymous.allowed_to?(:view_gitweb, project)
        
        read << "redmine"

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

        conf.permissions = [permissions]
			end
      
      ga_repo.save
      ga_repo.apply
			
      #remove local copy
		  `rm -Rf #{local_dir}`

			lockfile.flock(File::LOCK_UN)
		end
		@recursionCheck = false
	end
end
