class AddPatternToRepositories < ActiveRecord::Migration
  def self.up
    add_column :repositories, :branch_pattern, :string
    add_column :repositories, :tag_pattern, :string
  end


  def self.down
    remove_column :repositories, :branch_pattern
    remove_column :repositories, :tag_pattern
  end
end
