class GitolitePublicKeysController < ApplicationController
  unloadable
  
  before_filter :require_login
  before_filter :set_user_variable
  before_filter :find_gitolite_public_key, :except => [:index, :new, :create]

  def index
    @status = if (session[:gitolite_public_key_filter_status]=params[:status]).nil?
      GitolitePublicKey::STATUS_ACTIVE
    elsif params[:status].blank?
        nil
    else
	params[:status].to_i
    end
    
    scope = @user.gitolite_public_keys
    scope = scope.all if @status
    @gitolite_public_keys = scope

    respond_to do |format|
      format.html # index.html.erb
      format.json  { render :json => @gitolite_public_keys }
    end
  end
  
  def edit
  end

  def update
    if params[:public_key][:active]
      status = params[:public_key].delete(:active).to_i
      if status == GitolitePublicKey::STATUS_ACTIVE
        @gitolite_public_key.active = true
      elsif status == GitolitePublicKey::STATUS_LOCKED
        @gitolite_public_key.active = false
      end
    end

    if @gitolite_public_key.update_attributes(params[:public_key].permit(:active))
      flash[:notice] = l(:notice_public_key_updated)
      redirect_to url_for(:action => 'index', :status => session[:gitolite_public_key_filter_status])
    else
      render :action => 'edit'
    end
  end
  
  def new
    key_params = ActionController::Parameters.new(user: @user)
    key_params.permit!
    @gitolite_public_key = GitolitePublicKey.new(key_params)
  end
  
  def create
    tmp_params = params.require(:public_key).permit(:title,:key,:active).merge(:user => @user)
    @gitolite_public_key = GitolitePublicKey.new(tmp_params.permit!)
    if @gitolite_public_key.save
      flash[:notice] = l(:notice_public_key_added)
      redirect_to url_for(:action => 'index', :status => session[:gitolite_public_key_filter_status])
    else
      render :action => 'new'
    end
  end
  
  def show
    respond_to do |format|
      format.html # show.html.erb
      format.json { render :json => @gitolite_public_key }
    end
  end

  protected
  
  def set_user_variable
    @user = User.current
  end
  
  def find_gitolite_public_key
    key = GitolitePublicKey.find_by_id(params[:id])
    if key and key.user == @user
      @gitolite_public_key = key
    elsif key
      render_403
    else
      render_404
    end
  end

end
