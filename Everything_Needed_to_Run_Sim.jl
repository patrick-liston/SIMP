

#### Function to sample trade_sizes and return the size for the trade we'll do
get_trade_size(real_qtys::Vector{Float64}) = StatsBase.sample(real_qtys)
#### Function to sample agent_ids and return the id that will trade 
get_trading_agent(sample_list::Vector{Int64}) = StatsBase.sample(sample_list)


########################################################
####### SET-UP FOR RANDOM AGENT TIMINGS AND STUFF ######
########################################################

########## GENERATE ALL TRADING TIMES #######
function findnearest(a::Vector{Int},x::Int)
    length(a) > 0 || return 0:-1
    r = searchsorted(a,x)
    length(r) > 0 && return r
    last(r) < 1 && return searchsorted(a,a[first(r)])
    first(r) > length(a) && return searchsorted(a,a[last(r)])
    x-a[last(r)] < a[first(r)]-x && return searchsorted(a,a[last(r)])
    x-a[last(r)] > a[first(r)]-x && return searchsorted(a,a[first(r)])
    return first(searchsorted(a,a[last(r)])):last(searchsorted(a,a[first(r)]))
end


function findnearest(a,x)
    length(a) > 0 || return 0:-1
    r = searchsorted(a,x)
    length(r) > 0 && return r
    last(r) < 1 && return searchsorted(a,a[first(r)])
    first(r) > length(a) && return searchsorted(a,a[last(r)])
    x-a[last(r)] < a[first(r)]-x && return searchsorted(a,a[last(r)])
    x-a[last(r)] > a[first(r)]-x && return searchsorted(a,a[first(r)])
    return first(searchsorted(a,a[last(r)])):last(searchsorted(a,a[first(r)]))
end

########################################################
#######            GET ORDERBOOK AT TIME          ######
########################################################
function import_orderbook(time::Int64, lob::DataFrame)
    index = findnearest(lob.ts,time)[1]
    if index>1   #If this row is not the first in then remove it from the dataframe
        delete!(lob, [1:index;]) #USE THIS TO REMOVE ROWS THAT DON'T MATTER ANYMORE
    end
    return  lob[1,:], lob
end

########################################################
#######           ADJUST ORDERBOOK LEVEL          ######
########################################################
function shift_lob(price::Float64, prices::Vector{Float64})
    current_price = (prices[21] +  prices[1]) / 2  #Get mid-point
    delta = price - current_price                  #Difference to mid-point - Shift order by this amount
    for i in 1:40                                  #Shift all the order prices (inplace)
        prices[i]+=delta
    end
    return prices
end


########################################################
#######      GET TRADE PRICE AND SIZES            ######
########################################################
function get_prices(lob_now::DataFrameRow)
    return  Vector{Float64}(lob_now[4:2:82,])
end

function get_volumns(lob_now::DataFrameRow)
    return Vector{Float64}(lob_now[5:2:83,])
end













########################################################
#######           GET AVLIABLE FUNDS          ######
########################################################
function get_avaliable_funds(accounts::Vector, agent_id::Int)
    available_shares=accounts[agent_id][2]
    available_cash=accounts[agent_id][3]
    #print("\n Avaliable Cash: ", available_cash, " Avaliable Sahres: ", available_shares)
    return available_cash, available_shares
end

function update_account_holdings(accounts::Vector, agent_id::Int, amount_traded::Float64, cash_amount::Float64)
    accounts[agent_id][2]+=round(amount_traded, digits=4)
    accounts[agent_id][3]+=round(cash_amount, digits=2)
    #print("\nUpdated account!", accounts[agent_id])
    return accounts
end

function update_account_holdings(accounts::Vector, agent_id::Int, amount_traded::Number, cash_amount::Number)
    if agent_id != length(accounts)
    print("\nThis one is causing an issue\nAMOUNT_TRADED: ", amount_traded, " CASH AMOUNT: ", cash_amount)
    print("\nAgent_id: ", agent_id)
    print("\nStock: ", accounts[agent_id][2]) 
    print("\nCash: ", accounts[agent_id][3]) 
    stop
    end

    accounts[agent_id][2]+=round(amount_traded, digits=4)
    accounts[agent_id][3]+=round(cash_amount, digits=2)
    #print("\nUpdated account!", accounts[agent_id])
    return accounts
end


function test(accounts::Vector, agent_id::Int, prices::Vector{Float64}, pos::Int, trade_size::Float64)
    max_trade_size = accounts[agent_id][3]/prices[pos]
    trade_size = ifelse(max_trade_size>lob_level_amount, trade_size, max_trade_size)#Check the agent can make this trade - If do NOT have enough stock - adjust it down               
    accounts[agent_id][3] += trade_size
end

########################################################################################################################################################################
########################################################################################################################################################################

#                                           EVERYTHING TO DO WITH STOP-LOSSES                                                            #

########################################################################################################################################################################
########################################################################################################################################################################

########################################################
#######           PLACE STOP-LOSS ORDER           ######
########################################################
#function place_stop_loss(sl_book::Vector,  order::Vector, current_time::Int, price::Float64, μ::Float64, σ::Float64 )
function place_stop_loss(sl_book,  order, price::Float64, μ::Float64, σ::Float64 )
    #Get info for the order - and calculate trigger price
    #print("\n\nThis is the order: ", order)
    amount = order[3]
    trigger_percent = (amount - μ) / σ #Calculate Z-score
    direction, trigger_percent = ifelse(order[2]==1, [0,trigger_percent] , [1,-trigger_percent]) #Get new order direction, and percentage
    trigger_price = price * (trigger_percent/100+1)

    #Combine order, and put into book
    order = [order[1], direction, amount, trigger_price, order[5]]
    insert_stop_loss_order(sl_book, order)
end


### FUNCTION TO EXTEND ORDER BOOK IF PRICE NOT PRESENT ###
function extend_orderbook(ob::Vector, location::Int, order::Vector{Float64})
    #Insert new order price and order
    insert!(ob,location, order)
end

########################################################
#######          PLACES ORDER INTO BOOK           ######
########################################################
function insert_stop_loss_order(book::Vector, order::Vector{Float64})
    order_price = order[4]
    important_info = [order_price, order[3], order[1]] #Price, amount, agent_id
    num_orders = length(book)
    if num_orders > 0 #Check there is at least one order in the book - otherwise, add the order in
    if order_price < first(book[1]) #Lowest price
        #Insert new order price and order
        extend_orderbook(book, 1, important_info)
    #If the new order has a HIGHER buy price than the orderbook - insert
    elseif order_price > book[num_orders][1] #Highesght price
        extend_orderbook(book, num_orders+1, important_info)
    #If the order is somewhere in the book already
    else
        current_index=1
        #Find the index of the correct price
        while current_index+1<=num_orders
            if order_price>book[current_index+1][1];      current_index += 1
            else ; return extend_orderbook(book, current_index+1, important_info);       end
        end #End while loop
    end #End else loop
    else #No orders in book - put the order in
        extend_orderbook(book, 1, important_info)
    end #End check the book contains orders
end #End function



########################################################
#######         GETS INFO FOR SL ORDER            ######
########################################################
function get_sl_info(sl_book::Vector, accounts::Vector, side::Bool)
    order = ifelse(side==false, first(sl_book), last(sl_book)) #If it's a sell, get the first/lowest priced order, else get the buy - highest/last order
    #order=first(sl_book)
    agent_id = Int(order[3])
    # print("\n\nThis is the side: " , side,"\n\nThis is the order that we're looking at: ", order, "\nThis will be the trade sise we use: ", order[2])
    return  order[2], agent_id, accounts[agent_id][4][1]
end


########################################################
#######      REMOVES EXECUTED SL ORDERS           ######
########################################################
#Function to update/remove the executed sl order
function update_sl_buys(sl_book::Vector, traded_amount::Number, trade_size::Float64)
    # print("\nThis is the stop-loss book: ", sl_book)
    # print("\nFirst order: ", first(sl_book)[2], "\nTrade_size: ",trade_size, "\nCOmbined difference: ", first(sl_book)[2]-trade_size)
    if last(sl_book)[2]-trade_size<=0.000001 || first(sl_book)[2] - traded_amount<=0.000001
        popfirst!(sl_book) #Remove Executed Sl
        # print("\npopped first")
        return 0
    else
        first(sl_book)[2]-=traded_amount #Reduce Executed Amount
        return 1
        # print("\nReduced amount")
    end
end
#Function to update/remove the executed sl order
function update_sl_sells(sl_book::Vector, traded_amount::Number, trade_size::Float64)
    if last(sl_book)[2]-trade_size<=0.000001 || last(sl_book)[2] - traded_amount<=0.000001
        pop!(sl_book) #Remove Executed Sl
        return 0
    else
        last(sl_book)[2]-=traded_amount #Reduce Executed Amount
        return  1
    end
end

########################################################
#######    UPDATE ACCOUNTS WHEN SL ORDER          ######
########################################################
function update_sl_accounts(sl_book::Vector, accounts::Vector, agent_id::Int)
    #first(sl_book)[2]-trade_size
    #If the stop-loss order is closed, Update the sl indicator within the account params
    if first(sl_book)[2]<=0
        accounts[agent_id][4][3]-=1
    end
end


########################################################
#######    SEARCH FOR AND CANCEL SL ORDER         ######
########################################################
function find_and_cancel_sl(sl_book::Vector, agent_id )
    agent_id=Float64(agent_id)
    found = find_index(sl_book, 0, agent_id)
    if found!=0 #If found, Cancel 
        #cancel_sl(sl_book, found)
        deleteat!(sl_book, found)
    end
    return found
end


########################################################
#######      REMOVE SL ORDER FROM BOOK            ######
########################################################
function cancel_sl(sl_book::Vector, location::Int)
    deleteat!(sl_book, location)
end

########################################################
#######      FIND LOCATION OD SL ORDER            ######
########################################################
function find_index(sl_book::Vector, found::Int, agent_id::Float64)
    checked = 1; book_length = length(sl_book)
    while found==0 && checked < book_length+1
        check, found = ifelse(sl_book[checked][3]!=agent_id, [1,0], [0,checked]) 
        checked+=1
        end
    return found
end



########################################################################################################################################################################
########################################################################################################################################################################

########################################################
#######  MAIN TRADE FUNCTION (includes SLs)       ######
########################################################
function proper_trade(accounts::Vector, prices::Vector{Float64}, amounts::Vector{Float64}, order::Vector, tracking_in, sl_sells::Vector{}, sl_buys::Vector{}, μ::Float64, σ::Float64)
    agent_id = Int(order[1])
    direction = Bool(order[2])
    trade_size = order[3]
    current_time = Int(order[5])
    cash_amount = 0
    available_cash, available_shares = get_avaliable_funds(accounts, agent_id) #Maximum the agent can spend
    if direction==1 #This will be a SELL - therefore look at bids
        ##############################  DO THE ACTUAL TRADE   ##############################
        price, pos, cash_amount, traded_amount, accounts, executed_trade, tracking_in = sell_order(accounts, prices, amounts, agent_id, trade_size, tracking_in)
        ################################# UPADATE TRACKING ##############################
        #print("\n", typeof(direction), typeof(order[5]))
        tracking_in =  tracking_info(tracking_in, price, prices, traded_amount, cash_amount, pos, direction, current_time, "N", accounts[agent_id][4][1]) #Agent_strat
#        if accounts[agent_id][4][1]=="S"; print("\n\n!!!!!!!Finished the execution of the spike - but may continue to execute SL orders!!!!\n\n"); end
        # ################################# (POSSIBLY) PLACE A STOP LOSS ##############################
        if rand(1:10)>9 && accounts[agent_id][4][3]<1   #Ensure that no SLs are already placed by this account AND radomly select if we should place one
            place_stop_loss(sl_sells, order, price, μ, σ )
            accounts[agent_id][4][3]+=1 #Update accounts so we know an order has been placed
 #           if typeof(accounts)!=Vector{Any} 
  #              print("\nNormal SL ruined it: ",accounts)
  #          end
        elseif rand(1:10)>9 && accounts[agent_id][4][3]>0   #Ensure that no SLs are already placed by this account AND radomly select if we should place one
            #Cancel SL_TRADE and place a new one
            #Find sl_trade - 
            found = find_and_cancel_sl(sl_sells, agent_id ) #Sear sl_sells for trade
            if found!=0 ; found = find_and_cancel_sl(sl_buys, agent_id ); end #If not in sel_sells, check sl_buys
            #Reduce num stop-losses on 
            accounts[agent_id][4][3]-=1 #Update accounts so we know an order has been removed
            
            ## PLACE A NEW SL ORDER
            place_stop_loss(sl_sells, order, price, μ, σ )
            accounts[agent_id][4][3]+=1 #Update accounts so we know an order has been placed
            #print("\nFound the sl order at: ",found , " Cancelled the order, placed a new order: ", sl_sells[find_index(sl_sells, 0, Float64(agent_id))])
   #         if typeof(accounts)!=Vector{Any} 
   #             print("\nMeesed up after stoploss order: ",accounts)
   #         end
        end
        ##############################  DETERMINE IF WE'VE TRIGGERED STOP-LOSSES & EXECUTE   ##############################
        while length(sl_sells)>1 && price < last(sl_sells)[1]
    #        if typeof(accounts)!=Vector{Any} 
    #            print("\nThis is what we got: ",accounts)
    #        end
     #       if accounts[agent_id][4][1]=="S"; print("\n\n!!!!!!!EXECUTING SL orders - ANY LOB EXTENSIONS ARE CUASED BY THAT!!!!\n\n"); end
            #Select the stop-loss order
            #print("\nAccounts:", accounts)
            # if typeof(accounts)!=Vector{Any} 
            #     print("\nThis is what we got: ",accounts)
            # end
      #      if typeof(accounts)!=Vector{Any} 
      #          print("\nDied before sl info: ",accounts)
      #      end
            trade_size, agent_id,  agent_strat = get_sl_info(sl_sells, accounts, true) #Trade_direction=0 - direction=false
            #Shift the LOB to the correct level 
            prices = shift_lob(price, prices) #Shift "prices" to the "correct" level
            # print("\n\n", sl_sells)
            # print("\nAbout to execute Stop-Loss SELL order: ", last(sl_sells), " Current price was: ", prices[1])
            #Execute Stop-loss buy 
            # print("\nThis was the order: ", last(sl_sells))
            #price, pos, cash_amount, traded_amount, accounts = buy_order(accounts, prices, amounts, agent_id, trade_size)

            price, pos, cash_amount, traded_amount, accounts, executed_trade, tracking_in = buy_order(accounts, prices, amounts, agent_id, trade_size, tracking_in) 

            # print("\nTraded amount: ", traded_amount, " cash amount: ", traded_amount, cash_amount)
            # print("\nUpdated  order: ", last(sl_sells))
            if traded_amount>0
            tracking_in =  tracking_info(tracking_in, price, prices, traded_amount, cash_amount, pos, false, current_time, "Y", agent_strat)
            # print("\nExecuted Stop-Loss SELL order: ", last(sl_sells))
            #Determine if the full trade was made - if  yes, update account tracking, else lave it
            update_sl_accounts(sl_sells, accounts, agent_id)

            #Determine if the full trade was made - if  yes, remove, else update
            double_counted = update_sl_sells(sl_sells, traded_amount, trade_size)
            end #Ensure that the trade happened - not ZERO trades allowed 
        end #End stop-loss excutions
        
        

    else   #This is a BUY order
        ##############################  DO THE ACTUAL TRADE   ##############################
        #price, pos, cash_amount, traded_amount, accounts = buy_order(accounts, prices, amounts, agent_id, trade_size)
        price, pos, cash_amount, traded_amount, accounts, executed_trade, tracking_in= buy_order(accounts, prices, amounts, agent_id, trade_size, tracking_in)
        ################################# UPADATE TRACKING ##############################
        # print("\nAgent strat: ", accounts[agent_id][4][1], typeof(accounts[agent_id][4][1]))
        # print("\nStop-loss: ", "N", "typoef: ", typeof("N"))
        # print("\nDirection: ", direction, "typoef: ", direction)
        tracking_in =  tracking_info(tracking_in, price, prices, traded_amount, cash_amount, pos, direction, current_time, "N", accounts[agent_id][4][1]) #Agent_strat
        ################################# (POSSIBLY) PLACE A STOP LOSS ##############################
        if rand(1:10)>9 && accounts[agent_id][4][3]<1   #Ensure that no SLs are already placed by this account AND radomly select if we should place one
            place_stop_loss(sl_buys, order, price, μ, σ )
            accounts[agent_id][4][3]+=1 #Update accounts so we know an order has been placed
        elseif rand(1:10)>9 && accounts[agent_id][4][3]>0   #Ensure that no SLs are already placed by this account AND radomly select if we should place one
            #Cancel SL_TRADE and place a new one
            #Find sl_trade - 
            found = find_and_cancel_sl(sl_sells, agent_id ) #Sear sl_sells for trade
            if found!=0 ; found = find_and_cancel_sl(sl_buys, agent_id ); end #If not in sel_sells, check sl_buys
            #Reduce num stop-losses on 
            accounts[agent_id][4][3]-=1 #Update accounts so we know an order has been removed
            
            ## PLACE A NEW SL ORDER
            place_stop_loss(sl_buys, order, price, μ, σ )
            accounts[agent_id][4][3]+=1 #Update accounts so we know an order has been placed
            #print("\nFound the sl order at: ",found , " Cancelled the order, placed a new order: ", sl_sells[find_index(sl_sells, 0, Float64(agent_id))])
        end
        ##############################  DETERMINE IF WE'VE TRIGGERED STOP-LOSSES & EXECUTE   ##############################
        double_counted=0
        while length(sl_buys)>1 &&  price > first(sl_buys)[1] && double_counted==0
            #Select the stop-loss order
            trade_size, agent_id,  agent_strat = get_sl_info(sl_buys, accounts, false)
            #Shift the LOB to the correct level 
            prices = shift_lob(price, prices) #Shift "prices" to the "correct" level
            #Execute Stop-loss sell 
            price, pos, cash_amount, traded_amount, accounts, executed_trade, tracking_in = sell_order(accounts, prices, amounts, agent_id, trade_size, tracking_in)
            tracking_in =  tracking_info(tracking_in, price, prices, traded_amount, cash_amount, pos, true, current_time, "Y", agent_strat) 
            #Determine if the full trade was made - if  yes, update account tracking, else lave it
            update_sl_accounts(sl_buys, accounts, agent_id)
            #Determine if the full trade was made - if  yes, remove, else update
            double_counted = update_sl_buys(sl_buys, traded_amount, trade_size)
        end #End stop-loss excutions

        
    end

    return price, traded_amount, cash_amount, pos, accounts, sl_sells, sl_buys
end #End trade function



function simple_trade(accounts::Vector, prices::Vector{Float64}, amounts::Vector{Float64}, order::Vector, tracking_in)
    agent_id = Int(order[1])
    direction = Bool(order[2])
    trade_size = order[3]
    current_time = Int(order[5])
    cash_amount = 0
    available_cash, available_shares = get_avaliable_funds(accounts, agent_id) #Maximum the agent can spend
    if direction==1 #This will be a SELL - therefore look at bids
        price, pos, cash_amount, traded_amount, accounts, executed_trade, tracking_in = sell_order(accounts, prices, amounts, agent_id, trade_size, tracking_in)
        ################################# UPADATE TRACKING ##############################
        #print("\n", typeof(direction), typeof(order[5]))
        tracking_in =  tracking_info(tracking_in, price, prices, traded_amount, cash_amount, pos, direction, current_time, "N", accounts[agent_id][4][1]) #Agent_strat

    else   #This is a BUY order
        ##############################  DO THE ACTUAL TRADE   ##############################
        #price, pos, cash_amount, traded_amount, accounts = buy_order(accounts, prices, amounts, agent_id, trade_size)
        price, pos, cash_amount, traded_amount, accounts, executed_trade, tracking_in = buy_order(accounts, prices, amounts, agent_id, trade_size, tracking_in)
        ################################# UPADATE TRACKING ##############################
        tracking_in =  tracking_info(tracking_in, price, prices, traded_amount, cash_amount, pos, direction, current_time, "N", accounts[agent_id][4][1]) #Agent_strat
    end

    return price, traded_amount, cash_amount, pos, accounts
end #End trade function



function simple_trade_old(accounts::Vector, prices::Vector{Float64}, amounts::Vector{Float64}, order::Vector, tracking_in)
    agent_id = Int(order[1])
    direction = Bool(order[2])
    trade_size = order[3]
    current_time = Int(order[5])
    cash_amount = 0
    available_cash, available_shares = get_avaliable_funds(accounts, agent_id) #Maximum the agent can spend
    if direction==1 #This will be a SELL - therefore look at bids
        ##############################  DO THE ACTUAL TRADE   ##############################
        price, pos, cash_amount, traded_amount, accounts, tracking_in= buy_order_new(accounts, prices, amounts, agent_id, trade_size, tracking_in) 
        ################################# UPADATE TRACKING ##############################
        tracking_in =  tracking_info(tracking_in, prices, traded_amount, cash_amount, pos, direction, current_time, "N", accounts[agent_id][4][1]) #Agent_strat

    else   #This is a BUY order
        ##############################  DO THE ACTUAL TRADE   ##############################
        #price, pos, cash_amount, traded_amount, accounts = buy_order(accounts, prices, amounts, agent_id, trade_size)
        price, pos, cash_amount, traded_amount, accounts, tracking_in= buy_order_new(accounts, prices, amounts, agent_id, trade_size, tracking_in) 
        ################################# UPADATE TRACKING ##############################
        tracking_in =  tracking_info(tracking_in, price, prices, traded_amount, cash_amount, pos, direction, current_time, "N", accounts[agent_id][4][1]) #Agent_strat
    end

    return prices[pos], traded_amount, cash_amount, pos, accounts
end #End trade function



function trade(accounts, prices, amounts, direction, agent_id, trade_size)
    cash_amount = 0
    available_cash, available_shares = get_avaliable_funds(accounts, agent_id) #Maximum the agent can spend
    if direction==1 #This will be a SELL - therefore look at bids
        ##############################  DO THE ACTUAL TRADE   ##############################
        price, pos, cash_amount, traded_amount, accounts, tracking_in = sell_order(accounts, prices, amounts, agent_id, trade_size, tracking_in)
        ################################# DETERMINE TRADE DIRECTION AND UPDATES ##############################

        # ################################# (POSSIBLY) PLACE A STOP LOSS ##############################
        

    else   #This is a BUY order
        ##############################  DO THE ACTUAL TRADE   ##############################
        #price, pos, cash_amount, traded_amount, accounts = buy_order(accounts, prices, amounts, agent_id, trade_size)
        price, pos, cash_amount, traded_amount, accounts, tracking_in= buy_order_new(accounts, prices, amounts, agent_id, trade_size, tracking_in) 
        ################################# DETERMINE TRADE DIRECTION AND UPDATES ##############################

        ################################# (POSSIBLY) PLACE A STOP LOSS ##############################
    end
#    print("\nStill returning this stuff")
    return price, traded_amount, cash_amount, pos, accounts
end #End trade function


mutable struct tracking
    trade_prices::Vector{Float64}
    trade_amounts::Vector{Float64}
    trade_sizes::Vector{Float64}
    trade_cashes::Vector{Float64}
    trade_directions::Vector{Char}
    simmed_times::Vector{Int128}
    LOB_depth_hit::Vector{Int128}
    stop_loss_order::Vector{Char}
    agent_type::Vector{Char}

    max_buys::Vector{Float64}
    max_sells::Vector{Float64}
    min_buys::Vector{Float64}
    min_sells::Vector{Float64}
end



function tracking_info(tracking,  price::Float64, prices::Vector{Float64}, traded_amount::Number, cash_amount::Number, pos::Int, trade_direction::Bool, current_time::Int, stop_loss_order::String, agent_type::String)
    # print("\nprice: ", typeof(price), " prices: ", typeof(prices), " traded_amount: ", typeof(traded_amount),
    # " cash_amount: ", typeof(cash_amount), " pos: ", typeof(pos), " trade_direction: ", typeof(trade_direction),
    # " current_time: ", current_time, " stop-loss:", typeof(stop_loss_order), " agent_type", typeof(agent_type) )
    append!(tracking.trade_prices,price)
    append!(tracking.trade_amounts,traded_amount)
    append!(tracking.trade_sizes,traded_amount)
    trade_direction = ifelse(trade_direction==1, "S", "B")
    append!(tracking.trade_directions, trade_direction)
    append!(tracking.trade_cashes, cash_amount)
    append!(tracking.simmed_times,current_time)
    append!(tracking.LOB_depth_hit,pos)

    append!(tracking.stop_loss_order,stop_loss_order)
    append!(tracking.agent_type,agent_type)


    append!(tracking.max_buys,prices[40])
    append!(tracking.max_sells,prices[20])
    append!(tracking.min_buys,prices[21])
    append!(tracking.min_sells,prices[1])
    return tracking
end



########################################################
#######            AGENT STRATEGIES              ######
########################################################



function Trend_Calc(trade_prices::Vector{Float64}, agent_params::Vector)
    try
        #Find if the price is going up or down
        #If the FIRST price is less than the LAST price - SELL
        if trade_prices[length(trade_prices)-agent_params[2]] < last(trade_prices)
            return 0 #SELL
        else
            return 1 #BUY
        end
    catch
    print("Not enough history - Chosing randomly")
    return rand(Bool,1,1)[1]
    end
end


function Mean_Calc(trade_prices::Vector{Float64}, agent_params::Vector)
    #Find if the price is above/below the Average
    #If the MEAN price is less than the LAST price -
    try
    if mean(last(trade_prices,agent_params[2])) < last(trade_prices)
        return 1 #BUY
    else
        return 0 #SELL
    end
    catch
        print("Not enough history - Chosing randomly")
        return rand(Bool,1,1)[1]
    end
end

# Spike agent will trade in the direction of the side with the most stop-loss orders
function Spike_Agent(sl_buys, sl_sells)
    sl_buys_amount = getindex.(sl_buys,2)
    sl_sells_amount = getindex.(sl_sells,2)
    return ifelse(sl_buys_amount>sl_sells_amount, true, false)
end
    



########################################################
#######           GENERATING ACCOUNTS             ######
########################################################
function generate_accounts(accounts::Vector, num_agents::Int, starting_shares::Float64, starting_cash::Float64, agent_params::Vector)
    start_agent=ifelse(length(accounts)>0,length(accounts), 0)
    for agent in start_agent+1:start_agent+num_agents
        push!(accounts, [agent, starting_shares, starting_cash, deepcopy(agent_params)])  #Deepcopy required so that when we update the list for each agent, it doesn't proliferate through all agents. i.e Need different pointer addresses for each agent.
    end
    return accounts
end
