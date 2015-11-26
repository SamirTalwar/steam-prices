---
---

intersperse = (object, [head, tail...]) ->
  result = [head]
  for value in tail
    result.push object
    result.push value
  result

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

  TYPES =
    all:
      id: 'all'
      name: 'All'
      default: true
      clause: ''
    discounted:
      id: 'discounted'
      name: 'Discounted'
      default: false
      clause: 'price.discounted_price is not null'

  link = ({type, date, today}) ->
    components = []
    components.push "type=#{type.id}" unless type.default
    components.push "date=#{date}" unless today
    "?#{components.join('&')}"

  sql = (query) ->
    Promise.resolve($.getJSON(QUERY_ENDPOINT + encodeURI(query)))

  parameters = new Promise((resolve, reject) ->
    uri = URI(window.location.href)
    query = uri.search(true)

    typeName = query.type ? 'all'

    specifiedDate = query.date
    if specifiedDate?
      resolve(typeName: typeName, date: specifiedDate)
    else
      resolve(sql('select max(date) today from prices')
        .then((data) -> typeName: typeName, date: data[0].today, today: true)))

  parameters
    .then(({typeName, date, today}) ->
      type = TYPES[typeName]
      return Promise.reject("\"#{typeName}\" is not a valid type.") unless type?

      document.title = "#{type.name} Steam Prices for #{date}"
      $('#date').val(date)
      picker = new Pikaday(
        field: $('#date')[0]
        format: 'YYYY-MM-DD'
        onSelect: () ->
          window.location = link({type: type, date: picker.toString(), today: false})
        defaultDate: date
      )

      $('#all-prices-link').attr('href', link({type: TYPES.all, date: date, today: today}))
      $('#all-prices-link').addClass('current-page') if type == TYPES.all
      $('#discounted-prices-link').attr('href', link({type: TYPES.discounted, date: date, today: today}))
      $('#discounted-prices-link').addClass('current-page') if type == TYPES.discounted

      sql("""
        select
          game.id gameId,
          game.name,
          game.country,
          price.original_price originalPrice,
          price.discounted_price discountedPrice
        from prices price
        join games game on game.id = price.id and game.country = price.country
        where price.date = date('#{date}')
        #{if type.clause then "and #{type.clause}" else ''}
      """))
    .then((data) ->
      gamePricesElement = $('.game-prices')

      if data.length == 0
        gamePricesElement.append($('<p>').text('There are no prices on record for this date.'))

      _(data)
        .groupBy((item) -> item.gameId)
        .pairs()
        .sortBy(([gameId, gamePrices]) -> gamePrices[0].name.toLowerCase())
        .forEach(([gameId, gamePrices]) ->
          url = "http://store.steampowered.com/app/#{gameId}"
          name = gamePrices[0].name

          gameElement = $('<div>')
            .append($('<a>')
              .attr('href', url)
              .text(name))
            .append(' - ')

          priceElements = intersperse('/', _(gamePrices)
            .sortBy((gamePrice) -> ORDER.indexOf(gamePrice.country))
            .map((gamePrice) ->
              if gamePrice.discountedPrice?
                $('<span>').addClass('discounted-price')
                  .text(CURRENCIES[gamePrice.country] + gamePrice.discountedPrice.toFixed(DECIMAL_PLACES))
              else
                $('<span>').addClass('original-price')
                  .text(CURRENCIES[gamePrice.country] + gamePrice.originalPrice.toFixed(DECIMAL_PLACES)))
            .value())

          for priceElement in priceElements
            gameElement.append(priceElement)

          gamePricesElement.append(gameElement)
        )
        .commit())
    .catch((reason) ->
      $('body').append $('<p>').text('There was an error. Check the logs for details.')
      console.error reason)
