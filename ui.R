# Loading necessary libraries for the user interface
library(shiny)
library(plotly)
library(shinyWidgets)
library(DT)
library(shinydashboard)
library(shinyjs)
library(shinyBS)

# Setting up the dashboard page elements
dashboardPage(
  
  dashboardHeader(title = ""),
  
  dashboardSidebar(
    sidebarMenu(id = "sidebar",
                menuItem("Main Configuration", tabName = "GlobalSettings"),
                menuItem("FIRE Configuration", tabName = "FIRESettings"),
                menuItem("FIRE Analysis", tabName = "FIRE"),
                menuItem("Retirement Parameters", tabName = "RetirementSettings"),
                menuItem("Retirement Projections", tabName = "Retirement")
    )
  ),
  
  dashboardBody(
    shinyjs::useShinyjs(),
    
    # Styling for the Shiny notification progress bar to center it on the screen
    tags$head(
      tags$style(
        HTML(".shiny-notification {
              height: 100px;
              width: 800px;
              position: fixed;
              top: 50%;
              left: 50%;
              transform: translate(-50%, -50%);
            }"
        )
      )
    ),
    
    tabItems(
      tabItem(tabName = "GlobalSettings",
              numericInput("age", "Enter Your Current Age:", 35, min = 1, max = 78, step = 1),
              numericInput("retirement_spending", "Annual Retirement Expenditure ($):", 40000, min = 1, step = 1),
              bsTooltip("retirement_spending", "Estimate your annual retirement expenses in today's dollars, adjusted for future inflation.", placement="right"),
              fixedRow(
                column(3,
                       numericInput("avg_stock_return_percentage", "Expected Stock Return (%):", 8.1, min = 0.1, max = 100, step = 0.1),
                       bsTooltip("avg_stock_return_percentage", "Average return from the stock market, used to model financial growth.", placement="right")
                ),
                column(3,
                       numericInput("stock_stddev", "Volatility of Stock Returns (%):", 17, min = 0, max = 75, step = 0.1)
                )
              ),
              plotlyOutput("stock_histogram"),
              fixedRow(
                column(3,
                       numericInput("avg_bond_return_percentage", "Expected Bond Return (%):", 2.4, min = 0.1, max = 100, step = 0.1),
                       bsTooltip("avg_bond_return_percentage", "Average yield of bonds, factoring into the projected earnings from bond investments.", placement="right")
                ),
                column(3,
                       numericInput("bond_stddev", "Volatility of Bond Returns (%):", 7, min = 0, max = 75, step = 0.1)
                )
              ),
              plotlyOutput("bond_histogram"),
              fixedRow(
                column(3,
                       numericInput("avg_inflation_percentage", "Expected Inflation Rate (%):", 2, min = 0.1, max = 100, step = 0.1),
                       bsTooltip("avg_inflation_percentage", "Predicted annual increase in prices, used to adjust financial forecasts.", placement="right")
                ),
                column(3,
                       numericInput("inflation_stddev", "Volatility of Inflation Rate (%):", 4, min = 0, max = 75, step = 0.1)
                )
              ),
              plotlyOutput("inflation_histogram"),
              tags$br(),
              actionButton('jumpToFireSettings', 'Continue to FIRE Configuration')
      ),
      tabItem(tabName = "FIRESettings",
              fixedRow(
                column(3,
                       numericInput("brokerage_amount", "Current Brokerage Investments ($):", value = 50000, min = 0, step = 1),
                       bsTooltip("brokerage_amount", "Amount currently invested through a brokerage account.", placement="right")
                ),
                column(3,
                       uiOutput("stock_slider")
                ),
                column(3,
                       uiOutput("bond_slider")
                )
              ),
              fixedRow(
                column(3,
                       numericInput("income", "Annual Post-Tax Income ($):", 60000, min = 1, step = 1),
                       bsTooltip("income", "Your income after taxes, used to estimate financial capability.", placement="right")
                ),
                column(3,
                       numericInput("spending", "Annual Pre-Retirement Spending ($):", 45000, min = 1, step = 1),
                       bsTooltip("spending", "Your yearly expenditures before retirement, adjusted for taxes.", placement="right")
                ),
                column(3,
                       uiOutput("savings")
                )
              ),
              fixedRow(
                column(3,
                       checkboxInput("rebalanceassets", "Annually Rebalance Assets in Brokerage", TRUE)
                ),
                column(3,
                       uiOutput("target_stock")
                ),
                column(3,
                       uiOutput("target_bond")
                )
              ),
              numericInput("income_growth_percentage", "Annual Income Growth (%):", 1, min = 0, max = 100, step = 0.1),
              bsTooltip("income_growth_percentage", "Expected percentage increase in income annually.", placement="right"),
              uiOutput("retirementSpending"),
              numericInput("target_withdrawl_percentage", "Planned Annual Withdrawal Rate (%):", 3, min = 0.1, step = 0.1),
              bsTooltip("target_withdrawl_percentage", "Percentage of the retirement fund you plan to withdraw each year; 3% is typically cautious.", placement="right"),
              numericInput("avg_tax_rate_percentage", "Average Tax Rate (%):", 7, min = 0.1, max = 100, step = 0.1),
              uiOutput("fire_target_ui"),
              tags$br(),
              actionButton('jumpToFire', 'Advance to FIRE Analysis')
      ),
      tabItem(tabName = "FIRE",
              downloadButton("downloadmontecarlo", "Download Pre-Retirement Monte Carlo Data"),
              tags$h3("Overview of Initial Monte Carlo Simulation:"),
              DT::dataTableOutput("montecarlo_table"),
              plotlyOutput("brokerage_graph"),
              plotlyOutput("hit_fire_target_graph"),
              tags$br(),
              actionButton('jumpToRetirementSettings', 'Proceed to Retirement Configuration')
      ),
      tabItem(tabName = "RetirementSettings",
              numericInput("retirementage", "Designated Retirement Age:", 65, min = 1, max = 100, step = 1),
              uiOutput("retirementyear"),
              uiOutput("retirementSpendingDup"),
              numericInput("retirementsavings", "Funds at Retirement ($):", 2000000, min = 1, step = 1),
              bsTooltip("retirementsavings", "Total savings you'll have available at the start of retirement.", placement="right"),
              fixedRow(
                column(3,
                       uiOutput("stock_current_slider")
                ),
                column(3,
                       uiOutput("bond_current_slider")
                )
              ),
              fixedRow(
                column(3,
                       uiOutput("target_stock_retirement")
                ),
                column(3,
                       uiOutput("target_bond_retirement")
                )
              ),
              fixedRow(
                column(3,
                       checkboxInput("useavglife", "Incorporate average life expectancy", TRUE)
                ),
                column(3,
                       uiOutput("setupavglife")
                )
              ),
              tags$br(),
              actionButton('jumpToRetirement', 'Move to Retirement Projections')
      ),
      tabItem(tabName = "Retirement",
              tags$h3("Preview of Initial Retirement Simulation:"),
              DT::dataTableOutput("montecarlo_table_retirement"),
              plotlyOutput("brokerage_retirement_graph"),
              plotlyOutput("broke_graph"),
              plotlyOutput("deceased_graph"),
              tags$br(),
              actionButton('jumpToAbout', 'Proceed to About Page')
      )
    )
  )
)
