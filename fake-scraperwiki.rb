module ScraperWiki
  def self.save_sqlite keys, rows, table
    puts "Saving to #{table}:"
    for row in rows
      p row
    end
    puts
  end
end
