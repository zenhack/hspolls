{ global =
    { scrape_interval = "15s"
    }

, scrape_configs =
    [ { job_name = "hspolls"
      , static_configs =
          [ { targets =
                [ "localhost:8000"
                ]
            }
          ]
      }
    ]
}
