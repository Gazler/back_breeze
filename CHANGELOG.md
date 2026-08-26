## [0.4.4] - 2026-08-26

### Features

- *(BackBreeze.Cache)* Support configurable cache backends ([eb30f8c](https://github.com/gazler/breeze/commit/eb30f8ca56091cd021084539e3ae093fe574c928))
- *(BackBreeze.Style)* Support max height contstraints ([87bce2e](https://github.com/gazler/breeze/commit/87bce2eae34332cdf9faccc086fb301aa273f3ca))
- *(BackBreeze.RenderCache)* Make os_mon opt-in for memory ([bd1c271](https://github.com/gazler/breeze/commit/bd1c271d7d91000dc7652aa3a3e8de70f305f0b8))

### Bug Fixes

- *(BackBreeze.Box.LayerMap)* Ensure parent fill works with unicode ([4b4bc8e](https://github.com/gazler/breeze/commit/4b4bc8e205396fe9b78d339e522aab14954716d5))
- *(BackBreeze.Box)* Preserve overlays beyond fixed-height bounds ([b16fa20](https://github.com/gazler/breeze/commit/b16fa209045c278bf32b683b439417a9235bb1fe))
- *(BackBreeze.Ucwidth)* Fallback to unicode_width if prim_tty missing ([73f403a](https://github.com/gazler/breeze/commit/73f403ac5d6678356a48948366e1bc2649e890fe))
- *(BackBreeze.Box)* Ensure that empty inline space is reserved ([766c871](https://github.com/gazler/breeze/commit/766c87148a919a0e38c50f8a938ff1384d999627))
- *(BackBreeze.RenderCache)* Size cache from available memory ([f1b12f6](https://github.com/gazler/breeze/commit/f1b12f6cfaa418da7809757398a767b715227ef3))
- *(BackBreeze.Grid)* Inherit parent bg in grid ([d3451d5](https://github.com/gazler/breeze/commit/d3451d5d4888bfb2b22697565786478eb59d0dec))
- *(BackBreeze.Box)* Fix absolute nested scroll bars ([b1a86d2](https://github.com/gazler/breeze/commit/b1a86d2b6945cf70cbd02ebe91fe3e8819d22931))

### Refactor

- *(BackBreeze.Box)* Extract layout concerns and streamline caching ([4955447](https://github.com/gazler/breeze/commit/49554474a2830829a33ba51039cf77aefd455fc4))

### Performance

- *(BackBreeze.Box.LayerMap)* Optimize composition ([1df66d8](https://github.com/gazler/breeze/commit/1df66d81913402d0263736b99d40f7723162cc11))
- *(BackBreeze.Box)* Avoid redundant layer map scans ([3046b7d](https://github.com/gazler/breeze/commit/3046b7dbc295f3ef955bd0c4cb7ddfcfed0d1c93))
## [0.4.1] - 2026-07-09

### Bug Fixes

- *(BackBreeze.Box)* Include rendered grid height for auto-height containers ([96641cd](https://github.com/gazler/breeze/commit/96641cd7a9ac0caefba6b3e35ee6ded4d130275d))
- *(BackBreeze.VirtualText)* Bypass render cache for uncached content ([4339639](https://github.com/gazler/breeze/commit/433963972c3e19d556e3cc719c149051969b0473))

### Refactor

- *(Breeze.Box)* Rendering internals ([7e619c8](https://github.com/gazler/breeze/commit/7e619c8289ab37869cc5e283b5d49dc826f4c29b))
## [0.4.0] - 2026-04-17

### Features

- *(BackBreeze.Box)* Change the sizing model to border-box ([1c2d863](https://github.com/gazler/breeze/commit/1c2d863b094bd516f51b30e9d6526bf4b7612174))
- *(BackBreeze.Style)* Add content repeat options ([9c26ad6](https://github.com/gazler/breeze/commit/9c26ad6a3353bae20582a2bd0acb3036aa88a1ee))
- *(BackBreeze.Grid)* Add grid gaps and preserve row overlay ordering ([39f479f](https://github.com/gazler/breeze/commit/39f479f9215160bf6734561fa358e0f5945dc539))
- *(BackBreeze.Style)* Add prepared text and virtual text sources ([cbea063](https://github.com/gazler/breeze/commit/cbea063239a45df3ac894cb04ccf48dd64f24498))

### Bug Fixes

- *(BackBreeze.Box)* Fix cell merging with unicode characters ([1925719](https://github.com/gazler/breeze/commit/1925719609847937697b4745908f7639ebf95ca0))
- *(BackBreeze.Box)* Keep child width on inline overflow-hidden ([3ac77d9](https://github.com/gazler/breeze/commit/3ac77d9ce46369dbb684e20eff6f946e0a3f4691))
- *(BackBreeze.Box)* Allow symbolic offsets in grids ([2007d54](https://github.com/gazler/breeze/commit/2007d542e6c882e91395f096817c3864d0b08ddb))
- *(BackBreeze.RenderCache)* Bound cached grid renders by memory usage ([2667701](https://github.com/gazler/breeze/commit/26677014b166dd6dce998cd0c7cf2f4266fd2df8))
- *(BackBreeze.Box)* Accumulate consecutive SGR sequences ([11004cd](https://github.com/gazler/breeze/commit/11004cd2a322faf5b2c535f49ad503215237116a))
- *(BackBreeze.Box)* Preserve wide glyph composition in plain renders ([813637c](https://github.com/gazler/breeze/commit/813637c4648d34a7121bf1d8723eff23712e36ec))
- *(BackBreeze.Box)* Stabilize retained layout composition and profiling ([ef72509](https://github.com/gazler/breeze/commit/ef72509efffab6382765e01cfd00d812f1039725))

### Performance

- *(BackBreeze.Box)* Retain structured child surfaces through composition ([4dc21f8](https://github.com/gazler/breeze/commit/4dc21f82c82726985d64ea29442f0244b06e60ff))
## [0.3.0] - 2026-03-19

### Features

- *(BackBreeze.Box)* Add render_with_dimensions for viewport metadata ([37d7bf2](https://github.com/gazler/breeze/commit/37d7bf2ecacd09cf423a974b94b8597678005bd9))
- *(viewport)* Clip overflow-hidden children and support horizontal child scroll ([8aa4f35](https://github.com/gazler/breeze/commit/8aa4f35cdbb762123a8b098ec0a8127c1b505478))
- *(BackBreeze.Style)* Handle overflow for horizontal scrolling ([d92ddf0](https://github.com/gazler/breeze/commit/d92ddf019eafcf9c50074b653f3ce333832f77a0))
- *(scrollbar)* Add vertical viewport scrollbar for overflow-hidden boxes ([3053e6c](https://github.com/gazler/breeze/commit/3053e6c3237aac8ea96d5bf7ff0889b37421225e))
- *(scrollbar)* Make scrollbar behavior and styling configurable ([4f94bbe](https://github.com/gazler/breeze/commit/4f94bbe1d1db083747bffeaa86e78d813b8ba49c))
- *(BackBreeze.Scrollbar)* Inherit border color if not set ([f9d1992](https://github.com/gazler/breeze/commit/f9d19926970518d821f1d9d23cfcafdb806022bc))
- *(BackBreeze.Grid)* Allow setting number of rows ([6a76dac](https://github.com/gazler/breeze/commit/6a76dacb767dfacf2817226a355c15c99339c57b))
- *(BackBreeze.Box)* Support width: :full ([f77cf12](https://github.com/gazler/breeze/commit/f77cf12fd4339705f681e1fcd1ca04fc48c60fd3))
- *(BackBreeze.Border)* Support rounded borders ([88eda61](https://github.com/gazler/breeze/commit/88eda61e304ae057f54fd671895630a29d4c4e0e))
- *(BackBreeze.Grid)* Support fixed heights on grids ([60f335e](https://github.com/gazler/breeze/commit/60f335e0a4201ce06bd0b9be7c042abf355c2860))
- *(BackBreeze.Box)* Support fixed positioning ([95557b9](https://github.com/gazler/breeze/commit/95557b9749d6df022874da2a8efae13d1216eee4))
- *(BackBreeze.BenchProfile)* Add render benchmarking and profiling ([6522b00](https://github.com/gazler/breeze/commit/6522b007ec4cf1309c06238eb68a45ccdd1a47f1))
- *(bench)* Support fixture-based benchmark scenarios ([a8ba867](https://github.com/gazler/breeze/commit/a8ba86744bc5a9469b0e014b1da66833aca6a278))
- *(BackBreeze.Style)* Add directional padding and text alignment ([eba9517](https://github.com/gazler/breeze/commit/eba95176f16f7b2a1ab47dd0825ab2d7891fa747))

### Bug Fixes

- *(viewport)* Clip overflow-hidden children using rendered bounds ([711dffe](https://github.com/gazler/breeze/commit/711dffe4ef1d23839a6200fbf2016801636dddef))
- *(scrollbar)* Address inset clipping and bottom-alignment edge cases ([7c96928](https://github.com/gazler/breeze/commit/7c96928f42dcafe073c0e0770540a79193c1be5d))
- *(scrollbar)* Restore proportional thumb sizing by default ([f796603](https://github.com/gazler/breeze/commit/f7966038714c17543e047efe4c04683930bd023d))
- *(BackBreeze.Box)* Fix calculation for dimensions ([43a2cde](https://github.com/gazler/breeze/commit/43a2cdee48be86d332efb4b0bc5c9a6855dbf5f1))
- *(BackBreeze.String)* Ignore escape sequences for reflow ([f9b4af1](https://github.com/gazler/breeze/commit/f9b4af135135c9af785be1ba536b3be48cbbe42b))
- *(BackBreeze.Box)* Fix layout dimensions and support height-full ([a9bb2aa](https://github.com/gazler/breeze/commit/a9bb2aa9bb8829437908d27058903d1bd66aa605))
- *(BackBreeze.Box)* Support :screen for children width and height ([2fb3b24](https://github.com/gazler/breeze/commit/2fb3b240ad4e21258dc4df5c5969c8fdcfeb2e2d))
- *(BackBreeze.Box)* Fix sizing calculations when building tree ([9d366d1](https://github.com/gazler/breeze/commit/9d366d145ff8baa1983735a09c18e08840367e9e))
- *(BackBreeze.Box)* Propagate nested dimension positions ([1ec6918](https://github.com/gazler/breeze/commit/1ec69189451a3dde4c5e06bc4f4b64473853b30e))
- *(BackBreeze.Box)* Clip child content inside bordered viewports ([d207a6c](https://github.com/gazler/breeze/commit/d207a6c500c858390c7bc22746b553ae736e9dae))
- *(BackBreeze.Box)* Improve overlay positioning and fill sizing ([b77bbfd](https://github.com/gazler/breeze/commit/b77bbfd06e7b4cbb867865819c0ab49878c50792))
- *(BackBreeze.Grid)* Pass terminal context to cached child renders ([45150aa](https://github.com/gazler/breeze/commit/45150aa91099682d340fbc7f8b1d432f8a170946))
- *(BackBreeze.Box)* Inherit container backgrounds into borders and scrollbars ([0ad3014](https://github.com/gazler/breeze/commit/0ad3014f301ed56f1521b356218e1bf74ab05604))

### Refactor

- *(BackBreeze.Scrollbar)* Move scrollbar functions into own module ([2ed53ca](https://github.com/gazler/breeze/commit/2ed53ca66535d0750185db01798d13098e2270da))

### Performance

- *(BackBreeze.Utils)* Speed up width and ANSI handling ([4fb88ea](https://github.com/gazler/breeze/commit/4fb88eacae6dee619bf13c93cf9f1755dc61175d))
- *(BackBreeze.Box)* Optimize layer map generation and composition ([7b8d405](https://github.com/gazler/breeze/commit/7b8d405f36c390314be28de2e2d8e198611c701a))
- *(BackBreeze.Grid)* Optimize grid composition and dimensions ([aeff429](https://github.com/gazler/breeze/commit/aeff4295127ea8047b5b7dcd67312cd040d567ad))
- *(BackBreeze.Box)* Reduce repeated layout and layer map work ([865b670](https://github.com/gazler/breeze/commit/865b670efcb2359cf715887f73a84dd91ce125ef))
- *(BackBreeze.Box)* Optimize overlay and grid composition paths ([517de99](https://github.com/gazler/breeze/commit/517de99196325681a979fa012872d0189bd1db23))
- *(BackBreeze.Box)* Push layer-map rendering deeper through grids ([4dbd4f2](https://github.com/gazler/breeze/commit/4dbd4f26741e66c5161044bd54fdcbd786fde0e0))
- *(BackBreeze.Box)* Add render cache for layer map composition ([36962b5](https://github.com/gazler/breeze/commit/36962b5dc79ce295a813c86415c536ce25806117))
- *(BackBreeze.RenderCache)* Add frame-scoped render caching ([9d0df5b](https://github.com/gazler/breeze/commit/9d0df5b0f9f0e838def96ded446d9e9733da528e))
- *(BackBreeze.RenderCache)* Add stable render cache entries ([9f3580e](https://github.com/gazler/breeze/commit/9f3580e91928e04091bb00e06dc9872460614b60))
## [0.2.1] - 2025-05-23

### Bug Fixes

- *(BackBreeze.String)* Support newline chars when reflowing ([16e09b8](https://github.com/gazler/breeze/commit/16e09b80f55af0588573fc9c84bc1c62151c5239))
## [0.2.0] - 2024-08-03

### Features

- *(style)* Allow :screen width and height ([bb51ee8](https://github.com/gazler/breeze/commit/bb51ee8eece0dec4c27d395967d23f95d5edd514))
- *(box)* Display :block for vertical joining ([104ece9](https://github.com/gazler/breeze/commit/104ece98961f5dd6dca7a31043ef665b112d75a0))
- *(style)* Allow setting border color ([85c0152](https://github.com/gazler/breeze/commit/85c01528249b53cd7c349a77437d7b2930ad4e4e))
- *(box)* Support display grid ([f5c05ce](https://github.com/gazler/breeze/commit/f5c05ce9fcfe97961f91cdc359582c0ef3e01888))
- *(style)* Handle text overflowing ([fd3b196](https://github.com/gazler/breeze/commit/fd3b1969f5cdf1151e17ce143590d5953cfe438f))
- *(style)* Allow offsets when reflowing text ([babba8a](https://github.com/gazler/breeze/commit/babba8a68633d8c1087904e69fff280563c1acb4))
## [0.1.0] - 2024-06-13
