# if defined? map
#   map.resources :public_keys, :controller => 'gitolite_public_keys', :path_prefix => 'my'
#   map.connect  'gitolite_hook', :controller => 'gitolite_hook', :action => 'index'
# else
#   ActionController::Routing::Routes.draw do |map|
#     map.resources :public_keys, :controller => 'gitolite_public_keys', :path_prefix => 'my'
#     map.connect  'gitolite_hook', :controller => 'gitolite_hook', :action => 'index'
#   end
# end

scope "my" do
  resources :public_keys, :controller => 'gitolite_public_keys'
end

post "gitolite_hook", :to => "gitolite_hook#index"
