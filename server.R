# Load necessary libraries
library(shiny)
library(tidyverse)
library(lubridate)
library(plotly)
library(shinyWidgets) 
library(DT)
library(shinydashboard)
library(shinyjs)
library(purrr)

# Set options to prevent scientific notation
options(scipen=999)

# Load and process male death projections
male_death_projections <- read_csv("Data/Death_Projection_M.csv") %>%
  gather(age, probability, `0`:`119`, factor_key=TRUE) %>%
  mutate(gender = "Male") %>%
  mutate(age = as.integer(as.character(age))) %>%
  data.frame()

# Load and process female death projections
female_death_projections <- read_csv("Data/Death_Projection_F.csv") %>%
  gather(age, probability, `0`:`119`, factor_key=TRUE) %>%
  mutate(gender = "Female") %>%
  mutate(age = as.integer(as.character(age))) %>%
  data.frame()

# Combine male and female death projections into one dataset
death_projections <- rbind(male_death_projections, female_death_projections)

# Define the server logic for the Shiny application
shinyServer(function(input, output, session) {
  
  # Source additional simulation functions
  source("simulations.R", local=TRUE)
  
  # Reactive expression for Monte Carlo pre-retirement simulations
  monte_carlo_preretirement <- reactive({
    num_simulations = 250  # Number of simulations to run
    # Create a data frame to hold simulation inputs and results
    df <- data.frame(age = input$age:80,
                     inflation_percentage = NA,
                     fire_target = round(fire_target(), 2),
                     hit_fire_goal = NA,
                     income = input$income,
                     income_growth_percentage = input$income_growth_percentage,
                     savings = 0,
                     brokerage_amount = input$brokerage_amount,
                     brokerage_stock_percentage = input$brokerage_stock_percentage,
                     brokerage_stock_amount = input$brokerage_amount * (input$brokerage_stock_percentage/100),
                     stock_return_percentage = NA,
                     brokerage_bond_percentage = input$brokerage_bond_percentage,
                     brokerage_bond_amount = input$brokerage_amount * (input$brokerage_bond_percentage/100),
                     bond_return_percentage = NA
    )
    
    # Run simulations with progress indication
    withProgress(message = 'Running Monte Carlo pre-retirement simulation', value = 0, {
      ret <- NULL
      for (i in 1:num_simulations) {
        if (is.null(ret)) {
          ret <- single_run_preretirement(df) %>% mutate(run = i)
        } else {
          ret <- dplyr::bind_rows(ret, single_run_preretirement(df) %>% mutate(run = i))
        }
        incProgress(1/num_simulations, detail = paste0((i/num_simulations)*100,"%"))
      }
    })
    return(ret)
  })
  
  # Reactive expression to calculate percentiles for brokerage values
  brokerage_percentiles <- reactive({
    p <- c(0.1, 0.25, 0.5, 0.75, 0.9)  # Percentiles to calculate
    p_funs <- purrr::map(p, ~purrr::partial(quantile, probs = .x, na.rm = TRUE)) %>% 
      purrr::set_names(nm = p)
    
    grp <- monte_carlo_preretirement() %>%
      dplyr::group_by(age) %>% 
      dplyr::summarize_at(vars(brokerage_amount), funs(!!!p_funs)) %>%
      data.frame() %>%
      dplyr::rename("10th_Percentile" = X0.1) %>%
      dplyr::rename("25th_Percentile" = X0.25) %>%
      dplyr::rename("Median" = X0.5) %>%
      dplyr::rename("75th_Percentile" = X0.75) %>%
      dplyr::rename("90th_Percentile" = X0.9)
    
    return(grp)
  })
  
  # Reactive expression for Monte Carlo retirement simulations
  monte_carlo_retirement <- reactive({
    num_simulations = 50  # Number of simulations to run
    # Create a data frame to hold simulation inputs and results
    df <- data.frame(age = input$retirementage:110,
                     year = retire_year(),
                     gender = NA,
                     deceased = 0,
                     broke = 0,
                     inflation_percentage = NA,
                     retirement_spending = input$retirement_spending,
                     brokerage_amount = input$retirementsavings,
                     brokerage_stock_percentage = input$brokerage_stock_current_percentage,
                     brokerage_stock_amount = input$retirementsavings * (input$brokerage_stock_current_percentage/100),
                     stock_return_percentage = NA,
                     brokerage_bond_percentage = input$brokerage_bond_current_percentage,
                     brokerage_bond_amount = input$retirementsavings * (input$brokerage_bond_current_percentage/100),
                     bond_return_percentage = NA
    )
    yrs = input$retirementage - input$age  # Calculate years until retirement
    
    # Run simulations with progress indication
    withProgress(message = 'Running Monte Carlo retirement simulation', value = 0, {
      ret <- NULL
      for (i in 1:num_simulations) {
        if (is.null(ret)) {
          ret <- single_run_retirement(df, yrs, death_projections) %>% mutate(run = i)
        } else {
          ret <- dplyr::bind_rows(ret, single_run_retirement(df, yrs, death_projections) %>% mutate(run = i))
        }
        incProgress(1/num_simulations, detail = paste0((i/num_simulations)*100,"%"))
      }
    })
    return(ret)
  })
  
  # Reactive expression to calculate percentiles for brokerage values during retirement
  brokerage_retirement_percentiles <- reactive({
    p <- c(0.1, 0.25, 0.5, 0.75, 0.9)  # Percentiles to calculate
    p_funs <- purrr::map(p, ~purrr::partial(quantile, probs = .x, na.rm = TRUE)) %>% 
      purrr::set_names(nm = p)
    
    grp <- monte_carlo_retirement() %>%
      dplyr::group_by(age) %>% 
      dplyr::summarize_at(vars(brokerage_amount), funs(!!!p_funs)) %>%
      data.frame() %>%
      dplyr::rename("10th_Percentile" = X0.1) %>%
      dplyr::rename("25th_Percentile" = X0.25) %>%
      dplyr::rename("Median" = X0.5) %>%
      dplyr::rename("75th_Percentile" = X0.75) %>%
      dplyr::rename("90th_Percentile" = X0.9)
    
    return(grp)
  })
  
  # Reactive expression to determine if FIRE goal was hit
  hit_fire_target <- reactive({
    grp <- monte_carlo_preretirement() %>%
      dplyr::group_by(age, hit_fire_goal) %>%
      summarize(cnt = n()) %>%
      mutate(hit_fire_goal = as.character(hit_fire_goal)) %>%
      mutate(hit_fire_goal = ifelse(hit_fire_goal == 1, "Hit_FIRE", "Missed_FIRE")) %>%
      pivot_wider(names_from = hit_fire_goal, values_from = cnt) %>%
      data.frame()
    
    return(grp)
  })
  
  # UI output for stock slider input
  output$stock_slider <- renderUI({
    sliderInput("brokerage_stock_percentage", "Brokerage Stock Percentage", value = 80, min = 0, max = 100, step = 1)
  })
  
  # UI output for bond slider input (disabled)
  output$bond_slider <- renderUI({
    shinyjs::disabled(sliderInput("brokerage_bond_percentage", "Brokerage Bond Percentage", value = 100-input$brokerage_stock_percentage, min=0, max=100))
  })
  
  # Reactive expression to calculate savings
  savings <- reactive({
    return(input$income - input$spending)
  })
  
  # Reactive expression to calculate savings percentage
  savings_percentage <- reactive({
    return(round(((input$income - input$spending) / input$income) * 100, 2))
  })
  
  # UI output to display savings
  output$savings <- renderUI({
    shiny::validate(
      need(!is.null(savings) & !is.null(savings_percentage()), 'Loading...')
    )
    tags$p(paste0("Savings: $", format(savings(), big.mark=",", scientific=FALSE), " (", savings_percentage(), "%)"), style="font-size:18px;")
  })
  
  # Reactive expression to calculate FIRE target
  fire_target <- reactive({
    tgt = (input$retirement_spending * (1+(input$avg_tax_rate_percentage/100))) * (100/input$target_withdrawl_percentage)
    return(tgt)
  })
  
  # UI output to display FIRE target
  output$fire_target_ui <- renderUI({
    shiny::validate(
      need(!is.null(fire_target()), 'Loading...')
    )
    tags$p(paste0("FIRE Target: $", format(fire_target(), big.mark=",", scientific=FALSE)), style="font-size:18px;")
  })
  
  # Reactive expression to generate normal distribution for stock returns
  stock_normal_dist <- reactive({
    return(rnorm(5000, mean=input$avg_stock_return_percentage, sd=input$stock_stddev))
  })
  
  # Reactive expression to generate normal distribution for bond returns
  bond_normal_dist <- reactive({
    return(rnorm(5000, mean=input$avg_bond_return_percentage, sd=input$bond_stddev))
  })
  
  # Reactive expression to generate normal distribution for inflation rates
  inflation_normal_dist <- reactive({
    return(rnorm(5000, mean=input$avg_inflation_percentage, sd=input$inflation_stddev))
  })
  
  # UI output to display retirement spending
  output$retirementSpending <- renderUI({
    tags$p(paste0("Retirement spending: $", format(input$retirement_spending, big.mark=",", scientific=FALSE)), style="font-size:18px;")
  })
  
  # Duplicate UI output to display retirement spending
  output$retirementSpendingDup <- renderUI({
    tags$p(paste0("Retirement spending: $", format(input$retirement_spending, big.mark=",", scientific=FALSE)), style="font-size:18px;")
  })
  
  # UI output for target stock percentage slider input
  output$target_stock <- renderUI({
    if (input$rebalanceassets) {
      sliderInput("target_stock_percentage", "Target Stock Percentage", value = 80, min = 0, max = 100, step = 0.1)
    }
  })
  
  # UI output for target bond percentage slider input (disabled)
  output$target_bond <- renderUI({
    if (input$rebalanceassets) {
      shinyjs::disabled(sliderInput("target_bond_percentage", "Target Bond Percentage", value = 100-input$target_stock_percentage, min=0, max=100))
    }
  })
  
  # UI output to render histogram of stock returns
  output$stock_histogram <- renderPlotly({
    plot_ly(x = ~stock_normal_dist(), type = "histogram") %>%
      layout(title = "Stock Returns Percentage Distribution",
             xaxis = list(title = "Return Percentage"),
             yaxis = list(title = "Number of Occurrences"))
  })
  
  # UI output to render histogram of bond returns
  output$bond_histogram <- renderPlotly({
    plot_ly(x = ~bond_normal_dist(), type = "histogram") %>%
      layout(title = "Bond Returns Percentage Distribution",
             xaxis = list(title = "Return Percentage"),
             yaxis = list(title = "Number of Occurrences"))
  })
  
  # UI output to render histogram of inflation rates
  output$inflation_histogram <- renderPlotly({
    plot_ly(x = ~inflation_normal_dist(), type = "histogram") %>%
      layout(title = "Inflation Percentage Distribution",
             xaxis = list(title = "Percentage"),
             yaxis = list(title = "Number of Occurrences"))
  })
  
  # UI output to render data table of Monte Carlo pre-retirement simulations
  output$montecarlo_table <- DT::renderDataTable({
    shiny::validate(
      need(!is.null(monte_carlo_preretirement()) & !is.na(monte_carlo_preretirement()), 'Loading...')
    )
    
    DT::datatable(
      monte_carlo_preretirement() %>% dplyr::filter(run == 1),
      rownames = FALSE,
      options = list(scrollX = TRUE),
      selection = 'none'
    )
  })
  
  # Download handler for pre-retirement Monte Carlo simulation results
  output$downloadmontecarlo <- downloadHandler(
    filename = function() {
      paste0("monte_carlo_preretirement", format(Sys.time(), "%Y-%m-%d"), ".csv", sep = "")
    },
    content = function(file) {
      write.csv(monte_carlo_preretirement(), file, row.names = FALSE)
    }
  )
  
  # Download handler for retirement Monte Carlo simulation results
  output$downloadmontecarloretirement <- downloadHandler(
    filename = function() {
      paste0("monte_carlo_retirement", format(Sys.time(), "%Y-%m-%d"), ".csv", sep = "")
    },
    content = function(file) {
      write.csv(monte_carlo_retirement(), file, row.names = FALSE)
    }
  )
  
  # UI output to render brokerage percentiles graph
  output$brokerage_graph <- renderPlotly({
    shiny::validate(
      need(!is.null(brokerage_percentiles()) & !is.na(brokerage_percentiles()), 'Loading...')
    )
    
    plot_ly(brokerage_percentiles(), x = ~age, y = ~`10th_Percentile`, type = "scatter", mode = "lines", name = '10% Percentile', line = list(color='rgb(205, 12, 24)')) %>%
      add_trace(x = ~age, y = ~`25th_Percentile`, name = '25% Percentile', line = list(color='rgb(15, 12, 240)')) %>%
      add_trace(x = ~age, y = ~`Median`, name = 'Median', line = list(color='rgb(0, 255, 0)')) %>%
      add_trace(x = ~age, y = ~`75th_Percentile`, name = '75% Percentile', line = list(color='rgb(15, 12, 240)')) %>%
      add_trace(x = ~age, y = ~`90th_Percentile`, name = '90% Percentile', line = list(color='rgb(205, 12, 24)')) %>%
      layout(title = "Brokerage Amount ($)",
             xaxis = list(title = "Age"),
             yaxis = list(title = "Brokerage Amount ($)"))
  })
  
  # UI output to render graph showing whether FIRE target was hit
  output$hit_fire_target_graph <- renderPlotly({
    shiny::validate(
      need(!is.null(hit_fire_target()) & !is.na(hit_fire_target()), 'Loading...')
    )
    
    plot_ly(hit_fire_target(), x = ~age, y = ~Hit_FIRE, name = 'Hit FIRE Goal',
            type = 'scatter', mode = 'none', stackgroup = 'one', groupnorm = 'percent', fillcolor = 'rgb(5, 245, 24)') %>%
      add_trace(x = ~age, y = ~Missed_FIRE, name = 'Missed FIRE Goal', fillcolor = 'rgb(205, 12, 24)') %>%
      layout(title = "Hit FIRE Target?",
             xaxis = list(title = "Age"),
             yaxis = list(title = "Percentage of simulations that hit FIRE target"))
  })
  
  # UI output to set up average life expectancy based on gender
  output$setupavglife <- renderUI({
    if (input$useavglife) {
      pickerInput('gender', 'Gender',
                  choices = c("Male", "Female"),
                  multiple = FALSE)
    }
  })
  
  # Reactive expression to calculate years until retirement
  years_until_retirement <- reactive({
    return(input$retirementage - input$age)
  })
  
  # Reactive expression to calculate retirement year
  retire_year <- reactive({
    return(as.integer(format(Sys.Date(), "%Y")) + years_until_retirement())
  })
  
  # UI output to display retirement year
  output$retirementyear <- renderUI({
    tags$p(paste0("You retire ", years_until_retirement(), " years from now in ", retire_year(), "."))
  })
  
  # UI output for current stock percentage slider input
  output$stock_current_slider <- renderUI({
    sliderInput("brokerage_stock_current_percentage", "Brokerage Stock Percentage", value = 20, min = 0, max = 100, step = 1)
  })
  
  # UI output for current bond percentage slider input (disabled)
  output$bond_current_slider <- renderUI({
    shinyjs::disabled(sliderInput("brokerage_bond_current_percentage", "Brokerage Bond Percentage", value = 100-input$brokerage_stock_current_percentage, min=0, max=100))
  })
  
  # UI output for target stock percentage slider input during retirement
  output$target_stock_retirement <- renderUI({
    sliderInput("target_stock_retirement_percentage", "Target Retirement Stock Percentage", value = 20, min = 0, max = 100, step = 1)
  })
  
  # UI output for target bond percentage slider input during retirement (disabled)
  output$target_bond_retirement <- renderUI({
    shinyjs::disabled(sliderInput("target_bond_retirement_percentage", "Target Retirement Bond Percentage", value = 100-input$target_stock_retirement_percentage, min=0, max=100))
  })
  
  # UI output to render data table of Monte Carlo retirement simulations
  output$montecarlo_table_retirement <- DT::renderDataTable({
    shiny::validate(
      need(!is.null(monte_carlo_retirement()) & !is.na(monte_carlo_retirement()), 'Loading...')
    )
    
    DT::datatable(
      monte_carlo_retirement() %>% dplyr::filter(run == 1),
      rownames = FALSE,
      options = list(scrollX = TRUE),
      selection = 'none'
    )
  })
  
  # UI output to render brokerage retirement percentiles graph
  output$brokerage_retirement_graph <- renderPlotly({
    shiny::validate(
      need(!is.null(brokerage_retirement_percentiles()) & !is.na(brokerage_retirement_percentiles()), 'Loading...')
    )
    
    plot_ly(brokerage_retirement_percentiles(), x = ~age, y = ~`10th_Percentile`, type = "scatter", mode = "lines", name = '10% Percentile', line = list(color='rgb(205, 12, 24)')) %>%
      add_trace(x = ~age, y = ~`25th_Percentile`, name = '25% Percentile', line = list(color='rgb(15, 12, 240)')) %>%
      add_trace(x = ~age, y = ~`Median`, name = 'Median', line = list(color='rgb(0, 255, 0)')) %>%
      add_trace(x = ~age, y = ~`75th_Percentile`, name = '75% Percentile', line = list(color='rgb(15, 12, 240)')) %>%
      add_trace(x = ~age, y = ~`90th_Percentile`, name = '90% Percentile', line = list(color='rgb(205, 12, 24)')) %>%
      layout(title = "Brokerage Amount ($)",
             xaxis = list(title = "Age"),
             yaxis = list(title = "Brokerage Amount ($)"))
  })
  
  # UI output to render graph of deceased status
  output$deceased_graph <- renderPlotly({
    shiny::validate(
      need(!is.null(monte_carlo_retirement()) & !is.na(monte_carlo_retirement()), 'Loading...')
    )
    
    grp <- monte_carlo_retirement() %>%
      dplyr::group_by(age, deceased) %>%
      summarize(cnt = n()) %>%
      mutate(deceased = as.character(deceased)) %>%
      mutate(deceased = case_when(deceased == 0 ~ "Alive",
                                  deceased == 1 ~ "Deceased",
                                  deceased == 2 ~ "No_Data")) %>%
      pivot_wider(names_from = deceased, values_from = cnt) %>%
      data.frame()
    
    p <- plot_ly(grp, x = ~age, y = ~Deceased, name = 'Deceased',
                 type = 'scatter', mode = 'none', stackgroup = 'one', groupnorm = 'percent', fillcolor = 'rgb(205, 12, 24)') %>%
      add_trace(x = ~age, y = ~Alive, name = 'Alive', fillcolor = 'rgb(2, 205, 24)')
    
    if (!is.null(grp$No_Data)) {
      p <- p %>% add_trace(x = ~age, y = ~No_Data, name = 'No mortality data available', fillcolor = 'rgb(5, 12, 245)')
    }
    
    p <- p %>%
      layout(title = "Alive or Deceased?",
             xaxis = list(title = "Age"),
             yaxis = list(title = "Percentage of simulations that ended year deceased"))
  })
  
  # UI output to render graph of financial status (available money or broke)
  output$broke_graph <- renderPlotly({
    shiny::validate(
      need(!is.null(monte_carlo_retirement()) & !is.na(monte_carlo_retirement()), 'Loading...')
    )
    
    grp <- monte_carlo_retirement() %>%
      dplyr::group_by(age, broke) %>%
      summarize(cnt = n()) %>%
      mutate(broke = as.character(broke)) %>%
      mutate(broke = case_when(broke == 0 ~ "AvailableMoney",
                               broke == 1 ~ "Broke")) %>%
      pivot_wider(names_from = broke, values_from = cnt) %>%
      data.frame()
    
    plot_ly(grp, x = ~age, y = ~AvailableMoney, name = 'Available Money',
            type = 'scatter', mode = 'none', stackgroup = 'one', groupnorm = 'percent', fillcolor = 'rgb(5, 245, 24)') %>%
      add_trace(x = ~age, y = ~Broke, name = 'Broke', fillcolor = 'rgb(205, 12, 24)') %>%
      layout(title = "Available Money or Broke?",
             xaxis = list(title = "Age"),
             yaxis = list(title = "Percentage of simulations that ended without being in debt"))
  })
  
  # Observers for navigation buttons
  observeEvent(input$jumpToGlobalSettings, {
    updateTabItems(session, "sidebar", selected="GlobalSettings")
  })
  observeEvent(input$jumpToFireSettings, {
    updateTabItems(session, "sidebar", selected="FIRESettings")
  })
  observeEvent(input$jumpToFire, {
    updateTabItems(session, "sidebar", selected="FIRE")
  })
  observeEvent(input$jumpToRetirementSettings, {
    updateTabItems(session, "sidebar", selected="RetirementSettings")
  })
  observeEvent(input$jumpToRetirement, {
    updateTabItems(session, "sidebar", selected="Retirement")
  })
  observeEvent(input$jumpToAbout, {
    updateTabItems(session, "sidebar", selected="About")
  })
})
