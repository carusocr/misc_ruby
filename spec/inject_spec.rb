require 'rspec'
require 'active_record'
require 'benchmark'

PROJECT_ROOT = File.expand_path('../..', __FILE__)

Dir.glob(File.join(PROJECT_ROOT, 'lib', '*.rb')).each do |file|
  require(file)
end

ActiveRecord::Base.establish_connection(
  adapter:  'sqlite3',
  database: File.join(PROJECT_ROOT, 'test.db')
)

class CreateSchema < ActiveRecord::Migration
  def self.up
    create_table :categories, force: true do |table|
      table.string :name
      table.string :body
      table.integer :parent_id
    end
  end
end

CreateSchema.suppress_messages { CreateSchema.migrate(:up) }

describe 'inject exercise' do
  context '#all_equal?' do
    it 'returns true if all elements are equal to the argument' do
      expect(all_equal?(1, [1, 1, 1])).to be_true
    end

    it 'returns false if any element is unequal to the argument' do
      expect(all_equal?(1, [2, 1, 1])).to be_false
      expect(all_equal?(1, [1, 2, 1])).to be_false
      expect(all_equal?(1, [1, 1, 2])).to be_false
    end
  end

  context '#count_equal' do
    it 'counts the number of elements equal to the argument' do
      expect(count_equal(1, [1, 2, 3, 1, 2, 3])).to eq(2)
    end

    it 'returns zero for an empty array' do
      expect(count_equal(1, [])).to eq(0)
    end
  end

  context '#nested_key' do
    it 'finds the nested key when present' do
      data = { outer: { inner: 'value' } }
      expect(nested_key([:outer, :inner], data)).to eq('value')
    end

    it 'returns nil when missing a level' do
      data = { other: 'value' }
      expect(nested_key([:outer, :inner], data)).to be_nil
    end
  end

  context Category, '#search' do
    it 'finds entries by keyword search' do
      Category.create! name: 'one', body: 'keyword1 other words'
      Category.create! name: 'two', body: 'keyword2'
      Category.create! name: 'three', body: 'keyword1 keyword2 other words'
      Category.create! name: 'four', body: 'keyword1 keyword2 other words'

      result = Category.search('keyword1 keyword2').map(&:name)

      expect(result).to match_array(%w(three four))
    end
  end

  context Category, '#find_by_path' do
    it 'finds a top-level category' do
      pending
      Category.create!(name: 'Findme')

      expect(Category.find_by_path('Findme').try(:name)).to eq('Findme')
    end

    it 'finds a nested category' do
      pending
      root = Category.create!(name: 'Root')
      child = Category.create!(name: 'Child', parent: root)
      Category.create!(name: 'Grandchild', body: 'Orphan')
      Category.create!(name: 'Grandchild', parent: child, body: 'Expected')
      Category.create!(name: 'Grandchild', body: 'Orphan')

      result = Category.find_by_path('Root/Child/Grandchild').try(:body)

      expect(result).to eq('Expected')
    end

    it 'returns nil when missing a level' do
      Category.create!(name: 'Root')

      result = Category.find_by_path('Root/Child/Grandchild')

      expect(result).to be_nil
    end
  end

  after { Category.delete_all }
end
