<?php

require '/opt/arc/vendor/autoload.php';

do {
   
    $request = getNextRequest();

    $handlerFile = explode(".", $_ENV['_HANDLER'])[0];
    $handlerFunction = explode(".", $_ENV['_HANDLER'])[1];

    require_once $_ENV['LAMBDA_TASK_ROOT'] . '/' . $handlerFile . '.php';
    $response = $handlerFunction($request['payload']);

    // Submit the response back to the runtime API.
    sendResponse($request['invocationId'], $response);
} while (true);

function getNextRequest()
{
    $client = new \GuzzleHttp\Client();
    $response = $client->get('http://' . $_ENV['AWS_LAMBDA_RUNTIME_API'] . '/2018-06-01/runtime/invocation/next');

    return [
      'invocationId' => $response->getHeader('Lambda-Runtime-Aws-Request-Id')[0],
      'payload' => json_decode((string) $response->getBody(), true)
    ];
}

function sendResponse($invocationId, $response)
{
    $client = new \GuzzleHttp\Client();
    $client->post(
    'http://' . $_ENV['AWS_LAMBDA_RUNTIME_API'] . '/2018-06-01/runtime/invocation/' . $invocationId . '/response',
       ['body' => json_encode($response)]
    );
}