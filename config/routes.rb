ActionController::Routing::Routes.draw do |map|
  map.namespace :admin do |admin|
    admin.resources :tags, :collection => {:cloud => :get}
  end
end