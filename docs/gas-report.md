| src/ERC20Forwarder.sol:ERC20Forwarder Contract |                 |       |        |        |         |
|------------------------------------------------|-----------------|-------|--------|--------|---------|
| Deployment Cost                                | Deployment Size |       |        |        |         |
|                                        1415777 |            6483 |       |        |        |         |
|                                                |                 |       |        |        |         |
| Function Name                                  | Min             | Avg   | Median | Max    | # Calls |
| UPGRADE_INTERFACE_VERSION                      |             583 |   583 |    583 |    583 |       3 |
| VERSION                                        |             666 |   666 |    666 |    666 |       3 |
| forwardCall                                    |            4772 | 45677 |  41534 | 104269 |      15 |
| getImplementation                              |             388 |   388 |    388 |    388 |       3 |
| getLogicRef                                    |            2426 |  2426 |   2426 |   2426 |       3 |
| getProtocolAdapter                             |             278 |  1389 |   2278 |   2278 |      36 |
| initialize                                     |           92519 | 92519 |  92519 |  92519 |     119 |
| owner                                          |             366 |  1585 |   2366 |   2366 |      41 |
| proxiableUUID                                  |             240 |   240 |    240 |    240 |       2 |
| upgradeToAndCall                               |            2893 | 94268 | 108666 | 160624 |      63 |

| src/draft/ERC20Forwarder.sol:ERC20Forwarder Contract |                 |       |        |        |         |
|------------------------------------------------------|-----------------|-------|--------|--------|---------|
| Deployment Cost                                      | Deployment Size |       |        |        |         |
|                                              1670660 |            7669 |       |        |        |         |
|                                                      |                 |       |        |        |         |
| Function Name                                        | Min             | Avg   | Median | Max    | # Calls |
| VERSION                                              |             688 |   688 |    688 |    688 |       4 |
| forwardCall                                          |            4769 | 51444 |  50090 | 107250 |      19 |
| getLogicRef                                          |            2448 |  2448 |   2448 |   2448 |       2 |
| initialize                                           |           92734 | 92734 |  92734 |  92734 |      21 |
| proxiableUUID                                        |             240 |   240 |    240 |    240 |       8 |
| reinitializeLogicRef                                 |            2381 | 16737 |  23747 |  23747 |       9 |

