# Migrating NCBO data

Steps for migration:

  1. Copy `settings.sample.rb` to `settings.rb`
  2. Populate the settings file with the values appropriate to your environment
  3. `gem install bundler`
  4. `bundle install`
  5. To run all of the migrations: `ruby all.rb`
  6. To run a particular migration: `ruby migration.rb` (some migration are dependent on others, you will get an error if you try to run a migration with a dependent migration that hasn't been run yet)