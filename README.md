# Exometer JSON reporter #

Copyright (c) 2015 Helium Systems, Inc.  All Rights Reserved.

## exometer_report_json

The exometer JSON reporter provides a way to push metrics collected by
exometer to an HTTP sink via `PUT` or `POST` requests. This provides a
general way to publish data to aggregation services with the only
requirement being that the service must be able to accept HTTP
requests and be able to accept JSON formatted data.

### Configuration

The JSON reporter has the following configuration options:

* `json_sink_url` - The URL of the sink where the HTTP requests should
  be made. The default value is `http://localhost
* `json_http_request_type` - The HTTP request type to use. The valid
  values are `put` or `post`. The default is `put` and `put` is also
  used if an invalid request type is specified.
* `hostname` - The hostname reported with each metric message sent to
  the sink. The default is the hostname of the local system.
