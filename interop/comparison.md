Benchmark

This benchmark compares the performance of Mint introducing a new config for window size and frame size.


## System

Benchmark suite executing on the following system:

<table style="width: 1%">
  <tr>
    <th style="width: 1%; white-space: nowrap">Operating System</th>
    <td>Linux</td>
  </tr><tr>
    <th style="white-space: nowrap">CPU Information</th>
    <td style="white-space: nowrap">Intel(R) Core(TM) i7-10750H CPU @ 2.60GHz</td>
  </tr><tr>
    <th style="white-space: nowrap">Number of Available Cores</th>
    <td style="white-space: nowrap">12</td>
  </tr><tr>
    <th style="white-space: nowrap">Available Memory</th>
    <td style="white-space: nowrap">62.62 GB</td>
  </tr><tr>
    <th style="white-space: nowrap">Elixir Version</th>
    <td style="white-space: nowrap">1.15.7</td>
  </tr><tr>
    <th style="white-space: nowrap">Erlang Version</th>
    <td style="white-space: nowrap">26.1.2</td>
  </tr>
</table>

## Configuration

Benchmark suite executing with the following configuration:

<table style="width: 1%">
  <tr>
    <th style="width: 1%">:time</th>
    <td style="white-space: nowrap">10 s</td>
  </tr><tr>
    <th>:parallel</th>
    <td style="white-space: nowrap">1</td>
  </tr><tr>
    <th>:warmup</th>
    <td style="white-space: nowrap">2 s</td>
  </tr>
</table>

## Statistics



Run Time

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Average</th>
    <th style="text-align: right">Devitation</th>
    <th style="text-align: right">Median</th>
    <th style="text-align: right">99th&nbsp;%</th>
  </tr>

  <tr>
    <td style="white-space: nowrap">Gun (with NO config change)</td>
    <td style="white-space: nowrap; text-align: right">0.23</td>
    <td style="white-space: nowrap; text-align: right">4.34 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.89%</td>
    <td style="white-space: nowrap; text-align: right">4.30 s</td>
    <td style="white-space: nowrap; text-align: right">4.43 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Mint (with config change)</td>
    <td style="white-space: nowrap; text-align: right">0.0558</td>
    <td style="white-space: nowrap; text-align: right">17.91 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.00%</td>
    <td style="white-space: nowrap; text-align: right">17.91 s</td>
    <td style="white-space: nowrap; text-align: right">17.91 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Mint (with NO config change)</td>
    <td style="white-space: nowrap; text-align: right">0.0242</td>
    <td style="white-space: nowrap; text-align: right">41.34 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.00%</td>
    <td style="white-space: nowrap; text-align: right">41.34 s</td>
    <td style="white-space: nowrap; text-align: right">41.34 s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">Gun (with NO config change)</td>
    <td style="white-space: nowrap;text-align: right">0.23</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Mint (with config change)</td>
    <td style="white-space: nowrap; text-align: right">0.0558</td>
    <td style="white-space: nowrap; text-align: right">4.13x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">Mint (with NO config change)</td>
    <td style="white-space: nowrap; text-align: right">0.0242</td>
    <td style="white-space: nowrap; text-align: right">9.52x</td>
  </tr>

</table>



Memory Usage

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">Average</th>
    <th style="text-align: right">Factor</th>
  </tr>
  <tr>
    <td style="white-space: nowrap">Gun (with NO config change)</td>
    <td style="white-space: nowrap">12.55 KB</td>
    <td>&nbsp;</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Mint (with config change)</td>
    <td style="white-space: nowrap">12.64 KB</td>
    <td>1.01x</td>
  </tr>
    <tr>
    <td style="white-space: nowrap">Mint (with NO config change)</td>
    <td style="white-space: nowrap">12.63 KB</td>
    <td>1.01x</td>
  </tr>
</table>