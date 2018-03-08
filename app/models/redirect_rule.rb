class RedirectRule < ActiveRecord::Base
  extend Redirector::RegexAttribute
  regex_attribute :source

  attr_accessible :source,
                  :source_is_regex,
                  :destination,
                  :active,
                  :source_is_case_sensitive if Redirector.active_record_protected_attributes?

  validates :source, :destination, presence: true
  validates :active, inclusion: { in: ['0', '1', true, false] }

  before_save :strip_source_whitespace

  def self.regex_expression
    if connection_mysql?
      '(redirect_rules.source_is_case_sensitive = :true AND :source REGEXP BINARY redirect_rules.source) OR '+
      '(redirect_rules.source_is_case_sensitive = :false AND :source REGEXP redirect_rules.source)'
    else
      '(redirect_rules.source_is_case_sensitive = :true AND :source ~ redirect_rules.source) OR '+
      '(redirect_rules.source_is_case_sensitive = :false AND :source ~* redirect_rules.source)'
    end
  end

  def self.match_sql_condition
    <<-SQL
      redirect_rules.active = :true AND
      ((source_is_regex = :false AND source_is_case_sensitive = :false AND LOWER(redirect_rules.source) = LOWER(:source)) OR
      (source_is_regex = :false AND source_is_case_sensitive = :true AND #{'BINARY' if connection_mysql?} redirect_rules.source = :source) OR
      (source_is_regex = :true AND (#{regex_expression})))
    SQL
  end

  def self.match_for(source)
    match_scope = where(match_sql_condition.strip, {:true => true, :false => false, source: source})
    match_scope = match_scope.order('redirect_rules.source_is_regex ASC, LENGTH(redirect_rules.source) DESC')
  end

  def self.destination_for(source, environment)
    rule = match_for(source)
    rule.evaluated_destination_for(source) if rule
  end

  def evaluated_destination_for(request_path)
    if source_is_regex? && request_path =~ source_regex
      matches = $~
      number_of_grouped_matches = matches.length - 1
      final_destination = destination.dup

      number_of_grouped_matches.downto(1) do |index|
        final_destination.gsub!(/\$#{index}/, matches[index].to_s)
      end

      final_destination
    else
      destination
    end
  end

  private

  def self.connection_mysql?
    connection.adapter_name.downcase.include?('mysql')
  end

  def strip_source_whitespace
    self.source = self.source.strip
  end

end
