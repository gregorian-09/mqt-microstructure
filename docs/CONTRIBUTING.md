# Contributing

Thank you for considering contributing to the MQT microstructure library.

---

## Code Conventions

### Naming

| Element | Convention | Example |
|---------|-----------|---------|
| Classes | `CMqt` + PascalCase | `CMqtKyleLambda` |
| Structs | `Mqt` + PascalCase | `MqtTick`, `MqtConfig` |
| Methods | PascalCase | `AverageQuotedSpread()` |
| Fields | `m_` prefix + snake_case | `m_tick_collector` |
| Parameters | snake_case | `lookback`, `order_size` |
| Enums | `ENUM_MQT_` prefix | `ENUM_MQT_MARKET_REGIME` |
| Enum values | `MQT_` prefix | `MQT_REGIME_STRESSED` |
| Defines | `MQT_` prefix | `MQT_MAX_BOOK_DEPTH` |

### Style

- **Access via `.`**, not `->` — MQL5 object descriptors accept both, but `.` is idiomatic
- All class member fields are **private** with public accessors
- Use `int` for lookback windows and counts; `long` for millisecond timestamps
- Use `double` for all price and volume calculations
- Include guards are `MQT_MODULENAME_MQH` in `#ifndef`/`#define`/`#endif`

### Documentation

Every public method must have a JavaDoc block:

```cpp
/**
 * Brief description.
 *
 * Longer description if needed.
 *
 * @param param_name  Description.
 * @return  Description.
 */
```

Fields get trailing annotations:

```cpp
int m_window;  /*!< OLS regression window in number of ticks */
```

---

## Adding a New Analyzer

1. Create the file `Microstructure/YourAnalyzer.mqh`
2. Add a `/** @file */` header and include guard
3. Define your class with `CMqt` prefix
4. Implement `Init()` returning `bool`, and `LastError()` returning `int`
5. Add a module flag to `ENUM_MQT_MODULE_FLAG` in `Constants.mqh`
6. Add accessor, allocation, and cleanup code in `EventCoordinator.mqh`
7. Add the `#include` to `Microstructure.mqh`
8. Document the class in `docs/API.md`

### Analyzer template

```mql5
/**
 * @file YourAnalyzer.mqh
 * @brief Brief description.
 */
#include "DataTypes.mqh"

#ifndef MQT_YOUR_ANALYZER_MQH
#define MQT_YOUR_ANALYZER_MQH

class CMqtYourAnalyzer
{
private:
   int    m_error;

public:
   CMqtYourAnalyzer() { m_error = MQT_ERR_OK; }

   /**
   * Initialise the analyzer.
   * @return true on success.
   */
   bool Init()
   {
      m_error = MQT_ERR_OK;
      return true;
   }

   /** @return Last error code. */
   int LastError() const { return m_error; }

   /**
    * Compute something.
    * @param input  Input parameter.
    * @return Computed value, or 0 on error.
    */
   double Compute(double input)
   {
      if (input <= 0)
      {
         m_error = MQT_ERR_INVALID_PARAM;
         return 0;
      }
      // ... computation ...
      return result;
   }
};

#endif
```

---

## Testing

This library does not have a formal test suite (MQL5 lacks a standard testing framework).  
Instead, verify correctness by:

1. **Compile** the `examples/test_all_modules.mq5` EA in MetaEditor
2. **Run** on a demo account with a liquid symbol (EURUSD, GBPUSD)
3. **Check** the Experts log for `MQT:` prefixed error messages
4. **Compare** VPIN ≈ 0.5 for random flow, Kyle's lambda in range [1e-8, 1e-6] for FX
5. **Visualise** by logging `MqtMicrostructureStats::ToString()` every 60 seconds

---

## Pull Request Process

1. Ensure your code compiles on MT5 build 1720+
2. Add JavaDoc comments for all new public methods
3. Update `docs/API.md` with the new class/method
4. If your change adds a concept, update `docs/MICROSTRUCTURE.md`
5. Open a PR with a descriptive title and the `[MODULE]` prefix

---

## Project Structure for Contributors

```
include/
  Microstructure.mqh              ← add new #include here
  Microstructure/
    Constants.mqh                 ← add new module flags here
    Config.mqh                    ← add new config fields here
    DataTypes.mqh                 ← add new structs here
    YourNewModule.mqh             ← your file
    EventCoordinator.mqh          ← add allocation + accessor here
docs/
  API.md                          ← add class reference here
  MICROSTRUCTURE.md               ← add concept explanation here
  ARCHITECTURE.md                 ← update diagrams if needed
```
