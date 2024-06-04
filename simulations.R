# Function to simulate a single run for pre-retirement financial calculations
single_run_preretirement <- function(df) {
  # Convert df to a matrix for faster calculations
  df <- data.matrix(df)
  
  # Sample and assign stock and bond returns from their respective distributions
  df[,'stock_return_percentage'] = round(sample(stock_normal_dist(), nrow(df)), 2)
  df[,'bond_return_percentage'] = round(sample(bond_normal_dist(), nrow(df)), 2)
  
  # Sample and assign inflation rates
  df[,'inflation_percentage'] = round(sample(inflation_normal_dist(), nrow(df)), 2)
  
  # Update fire_target considering inflation for each year
  for (i in 2:nrow(df)) {
    df[i,]['fire_target'] = round(df[i,]['fire_target'] * (1 + (df[i,]['inflation_percentage']/100)), 2)
  }
  
  # Calculate the income and savings for each year considering income growth
  for (i in 2:nrow(df)) {
    df[i,]['income'] = round(df[i-1,]['income'] * (1 + (df[i,]['income_growth_percentage']/100)), 2)
    df[i,]['savings'] = round(df[i-1,]['income'] * (savings_percentage()/100), 2)
  }
  
  # Update the amounts in brokerage accounts based on the savings allocated to stocks and bonds
  df[,'brokerage_stock_amount'] = round(df[,'brokerage_stock_amount'] + (df[,'savings'] * (input$brokerage_stock_percentage/100)), 2)
  df[,'brokerage_bond_amount'] = round(df[,'brokerage_bond_amount'] + (df[,'savings'] * (input$brokerage_bond_percentage/100)), 2)
  
  # Calculate the new brokerage amounts considering returns and perform rebalancing if needed
  for (i in 2:nrow(df)) {
    df[i,]['brokerage_stock_amount'] = round(df[i-1,]['brokerage_stock_amount'] * (1 + (df[i,]['stock_return_percentage']/100)), 2)
    df[i,]['brokerage_bond_amount'] = round(df[i-1,]['brokerage_bond_amount'] * (1 + (df[i,]['bond_return_percentage']/100)), 2)
    
    if (input$rebalanceassets) {
      df[i,]['brokerage_amount'] = round(df[i,]['brokerage_stock_amount'] + df[i,]['brokerage_bond_amount'], 2)
      
      # Calculate adjustments needed for rebalancing
      delta_stock = round(df[i,]['brokerage_stock_amount'] - (df[i,]['brokerage_amount'] * (input$target_stock_percentage/100)), 2)
      delta_bond = round(df[i,]['brokerage_bond_amount'] - (df[i,]['brokerage_amount'] * (input$target_bond_percentage/100)), 2)
      
      # Apply rebalancing
      df[i,]['brokerage_stock_amount'] = df[i,]['brokerage_stock_amount'] - delta_stock
      df[i,]['brokerage_bond_amount'] = df[i,]['brokerage_bond_amount'] - delta_bond
    }
  }
  
  # Final updates to the brokerage details
  df[,'brokerage_amount'] = df[,'brokerage_stock_amount'] + df[,'brokerage_bond_amount']
  df[,'brokerage_stock_percentage'] = round((df[,'brokerage_stock_amount'] / df[,'brokerage_amount']) * 100, 2)
  df[,'brokerage_bond_percentage'] = round((df[,'brokerage_bond_amount'] / df[,'brokerage_amount']) * 100, 2)
  
  # Determine if the FIRE goal has been met
  df[,'hit_fire_goal'] = df[,'brokerage_amount'] >= df[,'fire_target']
  
  # Reset first row calculations to NA for certain variables as they do not apply to the starting conditions
  df[1,]['inflation_percentage'] = NA
  df[1,]['savings'] = NA
  df[1,]['income_growth_percentage'] = NA
  df[1,]['stock_return_percentage'] = NA
  df[1,]['bond_return_percentage'] = NA
  
  # Convert matrix back to data frame before returning
  df <- data.frame(df)
  return(df)
}

# Function to simulate a single retirement run taking into account lifespan and financials
single_run_retirement <- function(df, yrs, death_projections) {
  # Convert the dataframe to matrix for faster operations
  df <- data.matrix(df)
  
  # Calculate the retirement spending adjusted for inflation over the years
  spending = input$retirement_spending
  for (i in 1:yrs) {
    spending = spending * (1 + (sample(inflation_normal_dist(), 1)/100))
  }
  df[,'retirement_spending'] = round(spending, 2)
  
  # Update the year of retirement for each row in dataframe
  for (i in 2:nrow(df)) {
    df[i,]['year'] = df[i-1,]['year'] + 1
  }
  
  # Adjust for mortality based on the death projections and user gender if average life is considered
  if (input$useavglife) {
    for (i in 2:nrow(df)) {
      mortality_df <- death_projections %>%
        filter(gender %in% input$gender) %>%
        filter(age == df[i,]['age']) %>%
        filter(Year == df[i,]['year'])
      
      # Assign mortality based on the projections
      if (nrow(mortality_df) != 0) {
        if (df[i-1,]['deceased'] == 0 & runif(1) <= mortality_df$probability) {
          df[i,]['deceased'] = 1
        } else if (df[i-1,]['deceased'] == 1) {
          df[i,]['deceased'] = 1
        }
      } else {
        df[i,]['deceased'] = 2  # Mark as no data available
      }
    }
  }
  
  # Sample and assign stock and bond returns
  df[,'stock_return_percentage'] = round(sample(stock_normal_dist(), nrow(df)), 2)
  df[,'bond_return_percentage'] = round(sample(bond_normal_dist(), nrow(df)), 2)
  
  # Update retirement spending considering inflation
  for (i in 2:nrow(df)) {
    df[i,]['retirement_spending'] = round(df[i,]['retirement_spending'] * (1 + (df[i,]['inflation_percentage']/100)), 2)
  }
  
  # Calculate new brokerage amounts after accounting for spending and returns
  for (i in 2:nrow(df)) {
    df[i,]['brokerage_stock_amount'] = round(df[i-1,]['brokerage_stock_amount'] * (1 + (df[i,]['stock_return_percentage']/100)), 2)
    df[i,]['brokerage_bond_amount'] = round(df[i-1,]['brokerage_bond_amount'] * (1 + (df[i,]['bond_return_percentage']/100)), 2)
    
    df[i,]['brokerage_stock_amount'] = round(df[i,]['brokerage_stock_amount'] - (df[i,]['retirement_spending'] * (input$target_stock_retirement_percentage/100)), 2)
    df[i,]['brokerage_bond_amount'] = round(df[i,]['brokerage_bond_amount'] - (df[i,]['retirement_spending'] * (input$target_bond_retirement_percentage/100)), 2)
    
    df[i,]['brokerage_amount'] = round(df[i,]['brokerage_stock_amount'] + df[i,]['brokerage_bond_amount'], 2)
    
    # Rebalance the retirement funds if needed
    delta_stock = round(df[i,]['brokerage_stock_amount'] - (df[i,]['brokerage_amount'] * (input$target_stock_retirement_percentage/100)), 2)
    delta_bond = round(df[i,]['brokerage_bond_amount'] - (df[i,]['brokerage_amount'] * (input$target_bond_retirement_percentage/100)), 2)
    df[i,]['brokerage_stock_amount'] = df[i,]['brokerage_stock_amount'] - delta_stock
    df[i,]['brokerage_bond_amount'] = df[i,]['brokerage_bond_amount'] - delta_bond
  }
  
  # Update the final amounts for brokerage and percentages
  df[,'brokerage_amount'] = df[,'brokerage_stock_amount'] + df[,'brokerage_bond_amount']
  df[,'brokerage_stock_percentage'] = round((df[,'brokerage_stock_amount'] / df[,'brokerage_amount']) * 100, 2)
  df[,'brokerage_bond_percentage'] = round((df[,'brokerage_bond_amount'] / df[,'brokerage_amount']) * 100, 2)
  
  # Determine if the account has gone broke
  df[,'broke'] = df[,'brokerage_amount'] <= 0
  
  # Reset initial conditions for certain calculations as they do not apply
  df[1,]['inflation_percentage'] = NA
  df[1,]['stock_return_percentage'] = NA
  df[1,]['bond_return_percentage'] = NA
  
  # Convert matrix back to data frame and return
  df <- data.frame(df)
  df$gender = input$gender  # Assign gender for the simulation based on user input
  
  return(df)
}
