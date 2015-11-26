---
---

$ ->
  QUERY_ENDPOINT = 'https://free-ec2.scraperwiki.com/eccap3i/1c33e251880042f/sql/?q='
  $('.query-endpoint').append($('<a>')
    .attr('href', QUERY_ENDPOINT + encodeURI('select * from games limit 10'))
    .append($('<span>').html(QUERY_ENDPOINT.replace(/\//g, '<wbr/>/')))
    .append($('<em>').html('&lt;Your&nbsp;SQL&nbsp;Query&gt;')))
  $('.sql-info').show()

  ORDER = ['uk', 'us', 'fr']
  CURRENCIES =
    uk: '\u00a3'
    us: '$'
    fr: '\u20ac'
  DECIMAL_PLACES = 2

  sql = (query) ->
    Promise.resolve($.getJSON(QUERY_ENDPOINT + encodeURI(query)))

  date = new Promise((resolve, reject) ->
    url = URI(window.location.href)
    specifiedDate = url.search(true).date
    if specifiedDate?
      resolve(specifiedDate)
    else
      resolve(sql('select max(date) today from prices')
        .then((data) -> data[0].today)))

  date
    .then((today) ->
      document.title = "Steam Prices for #{today}"
      $('.today').text(today)

      sql("""
        select
          game.id gameId,
          game.name,
          game.country,
          price.original_price originalPrice,
          price.discounted_price discountedPrice
        from prices price
        join games game on game.id = price.id and game.country = price.country
        where price.date = date('#{today}')
        and price.discounted_price is not null
      """))
    .then((data) ->
      gamePricesElement = $('.game-prices')

      _(data)
        .groupBy((item) -> item.gameId)
        .pairs()
        .map((group) ->
          gameId = group[0]
          gamePrices = group[1]
          game = gamePrices[0]
          priceValues = _(gamePrices)
            .sortBy((gamePrice) -> ORDER.indexOf(gamePrice.country))
            .map((gamePrice) -> CURRENCIES[gamePrice.country] + gamePrice.discountedPrice.toFixed(DECIMAL_PLACES))

          {
            url: "http://store.steampowered.com/app/#{gameId}"
            name: game.name
            prices: priceValues.join('/')
          })
        .sortBy((game) -> game.name.toLowerCase())
        .forEach((game) ->
          gamePricesElement.append($('<div>')
            .append($('<a>')
              .attr('href', game.url)
              .text(game.name))
            .append(' - ')
            .append(game.prices)))
        .commit())
    .catch((reason) ->
      $('body').append $('<p>').text('There was an error. Check the logs for details.')
      console.error reason)
