using PyCall
using CSV
using Random
using DataFrames
using ProgressBars
using BenchmarkTools
using DelimitedFiles
using StatsBase
using Dates
using JDF
using PlotlyJS


MAIN_PATH = "/home/julia_user/Desktop/SIMP_Upload"
#Bring in the LOB extrapolation and Order execution functions 
include(MAIN_PATH * "/LOB_Extrapolation.jl")
include(MAIN_PATH * "/Buy_Sell_Order_Execution.jl")
include(MAIN_PATH * "/Everything_Needed_to_Run_Sim.jl")

plot_title = "test_plot" #Title for the plot you create.
save_output_data = 1
exp_name = "test_exp" #Expiriment name
MAIN_SAVE_PATH = MAIN_PATH * "/Data_Ouputs/"
new_sim = 1 #Toggle if you want to read in 
stop_loss_order = 0 #If you want to allow stop-loss orders within the market

save_data=0
total_sim_time=200_000
seed_num=rand(1:10000)
tracking_in = tracking([], [], [], [], [], [], [], [], [], [], [], [], [] )




date        = "20"
data_path   = MAIN_PATH *"/Data/"
model_path  = MAIN_PATH * "/Models"
if new_sim==1
    print("\nNew simulation, reading in data...")
    read_in_lob= CSV.read(MAIN_PATH*"/BTCUSDT_S_DEPTH/BTCUSDT_S_DEPTH_202111"*date*".csv", DataFrame)#, limit=2000000)
    read_in_data=CSV.read(MAIN_PATH*"/BTCUSDT_TRADES/BTCUSDT-trades-2021-11-"*date*".csv", DataFrame)#, limit=2000000)
    #read_in_real_qtys= readdlm(MAIN_PATH * "/Qtys.csv", ',', Float64)
    # read_in_real_qtys=CSV.read(MAIN_PATH *"/Qtys.csv", DataFrame)
    # read_in_real_qtys = vec(read_in_real_qtys[:qty])
    rng = MersenneTwister(1234)
    read_in_real_qtys=rand!(rng, zeros(50_000_000))/10
end


#Mean and STD used to calculate the size of the orders' stop-loss. (Intention to use the amount to find a Z-score which is then the %added/subtracted to the current price. Resulting in the stop-loss trigger price.)
μ = mean(read_in_real_qtys)
σ = std(read_in_real_qtys)
for num_sims in 1:2  #Number of simulations to run
    print("\n\n\n\nRunning simulation number: ", num_sims, "\n\n\n\n\n")
    seed_num=rand(1:10000)
    #seed_num  = 1234
    Random.seed!(seed_num)
    


############################
# TRIAL STUFF
############################
print("\nTrial Number ")
trial_num=seed_num
print(trial_num)

df=[]
stop_orders_to_execute=[]


print("\nCopying Data... ")
real_qtys=copy(first(read_in_real_qtys,total_sim_time*3))
data=copy(first(read_in_data,total_sim_time*3))
rename!(data,[:trade_Id,:price,:qty,:quoteQty,:time,:isBuyerMaker])
lob=copy(first(read_in_lob,total_sim_time*3))
print("\nRead in all data.")



### DOING TIMING STUFF  ###
start_time=first(data.time)
end_time=data.time[total_sim_time]
times_to_sim=first(data.time,total_sim_time)
real_trade_directions=first(data.isBuyerMaker,total_sim_time)
real_prices=first(data.price,total_sim_time)



########################################################
#######             SET AGENT LIMITS              ######
########################################################
accounts=[]


num_agents=10_000; starting_shares=100.015 ; starting_cash=5_000_000.00
agent_params=["R", 0.5, 0]
accounts=generate_accounts(accounts, num_agents, starting_shares, starting_cash, agent_params)

num_agents=1_000; starting_shares=100.015 ; starting_cash=5_000_000.00
agent_params=["T", 50, 0]
accounts=generate_accounts(accounts, num_agents, starting_shares, starting_cash, agent_params)

num_agents=1_000; starting_shares=100.015 ; starting_cash=5_000_000.00
agent_params=["M", 50, 0]
accounts=generate_accounts(accounts, num_agents, starting_shares, starting_cash, agent_params)

number_of_agents_in_simulation=length(accounts)
print("\nLength of accounts: ", number_of_agents_in_simulation)



#Need this to determine what each strategy will do  - trade_prices
# Selects an agent at random


#Select the right method for value/Direction calculation
function select_agent_calc_method(agent_strat::String, agent_params::Vector)
    if agent_strat=="R"
        real_trade_direction=rand(Bool,1,1)[1]
    elseif agent_strat=="Markov"
        real_trade_direction=Markov_Calc(previous_direction)
    elseif agent_strat=="T"
        real_trade_direction=Trend_Calc(tracking_in.trade_prices, agent_params)
    elseif agent_strat=="M"
        real_trade_direction=Mean_Calc(tracking_in.trade_prices, agent_params)      

    else
        print("This strategy hasn't been written yet: ", agent_strat)
        real_trade_direction=0
    end
    return  real_trade_direction
end


########################################################
#######          SPACE FOR AGENT TYPES            ######
########################################################
function update_order_book(lob::DataFrame, current_time::Int, price::Float64)
    lob_now, lob = import_orderbook(current_time, lob) #Import the LOB for the closest time
    prices = get_prices(lob_now::DataFrameRow) #Order prices
    amounts = get_volumns(lob_now::DataFrameRow) #Order amounts/size/volume
    prices = shift_lob(price, prices) #Shift "prices" to the "correct" level
    return prices, amounts, lob
end


#Run the main simulation - execute Stop-Loss are NOT orders permitted
function run_sim_step(previous_time, current_time, price,  real_qtys, accounts, tracking_in, lob, prices, amounts)
    #If we have moved a time-step. Update the LOB
    if previous_time != current_time
        prices, amounts, lob = update_order_book(lob, current_time, price)
    end

    #Get the agent Id and the trade size
    agent_id        = get_trading_agent(agents)
    trade_size      = get_trade_size(real_qtys)

    agent_strat     = accounts[agent_id][4][1]
    agent_params    = accounts[agent_id][4]
    trade_direction = select_agent_calc_method(agent_strat, agent_params)

    order           = [agent_id, trade_direction, trade_size, 0, current_time]

    price, traded_amount, cash_amount, pos, accounts = simple_trade(accounts, prices, amounts, order, tracking_in)
    
    return  current_time, price,  accounts, tracking_in, lob, prices, amounts
end # End simulation step function


#Run the main simulation - execute with Stop-Loss orders permitted
function run_sim_step_sl(previous_time, current_time, price,  real_qtys, accounts, tracking_in, lob, prices, amounts, sl_sells, sl_buys, μ, σ)
    #If we have moved a time-step. Update the LOB
    if previous_time != current_time
        prices, amounts, lob = update_order_book(lob, current_time, price)
    end

    #Get the agent Id and the trade size
    agent_id        = get_trading_agent(agents)
    trade_size      = get_trade_size(real_qtys)

    agent_strat     = accounts[agent_id][4][1]
    agent_params    = accounts[agent_id][4]
    trade_direction = select_agent_calc_method(agent_strat, agent_params)

    order           = [agent_id, trade_direction, trade_size, 0, current_time]

    price, traded_amount, cash_amount, pos, accounts, sl_sells, 
                        sl_buys = proper_trade(accounts, prices, amounts, order,tracking_in, sl_sells, sl_buys, μ, σ)
    
    return  current_time, price,  accounts, tracking_in, lob, prices, amounts, sl_sells, sl_buys
end # End simulation step function


########################################################
#######               Set Up STUFF               ######
########################################################

previous_time=0
trade_prices=[first(data[!,:price])]
price=data.price[findnearest(data.time,start_time)[1]]   #This should be the first trade price from BTCUSDT
#agents = [i for i in range(1, length = length(accounts))]
#If we allow a spike agent - count all agents, else only the non-spike agents
#agents = ifelse(spiked==1 ,  [i for i in range(1, length = length(accounts))],  [i for i in range(1, length = length(accounts)-1)])
agents = [i for i in range(1, length = length(accounts)-1)]


previous_price=price
lob_now, lob = import_orderbook(start_time, lob)

#previous_direction=real_trade_directions[index]
print("\nStarting simulation\n")
########################################################
#######               MAIN SIMULATION            ######
########################################################
 #tracking_in = tracking_6([], [], [], [], [], [], [], [], [], [], [], [], [] )
tracking_in = tracking([], [], [], [], [], [], [], [], [], [], [], [], [] )
sl_sells = []
sl_buys = []

prices, amounts, lob = update_order_book(lob, first(times_to_sim), price)

if stop_loss_order==1 #Picking which simulator to use - 1 if stop-loss permitted 0 if stop-loss NOT permitted
    total_time=range(1,length=length(times_to_sim))
    for n in ProgressBar(total_time)
        current_time=times_to_sim[n]
        
        previous_time, price,  accounts, tracking_in, lob, prices, amounts, 
                sl_sells, sl_buys = run_sim_step_sl(previous_time, current_time, price,  
                                    real_qtys, accounts, tracking_in, lob, prices, amounts, sl_sells, sl_buys, μ, σ)

    end #Stop-loss simulation


    else #Stop-loss orders NOT permitted

    total_time=range(1,length=length(times_to_sim))
    for n in ProgressBar(total_time)
        current_time=times_to_sim[n]

        previous_time, price,  accounts, tracking_in, lob,
        prices, amounts = run_sim_step(previous_time, current_time, price,  
                                    real_qtys, accounts, tracking_in, lob, prices, amounts )

    end #Non Stop-loss simulation

end #Picking which simulator to use



print("Finished Simulation")


print("\n\n\nWe COULD start plotting now - if everything went well")





########################################################
#######           SAVING DATAFRAMES               ######
########################################################

df          = DataFrame(time=tracking_in.simmed_times, price = tracking_in.trade_prices , max_price = tracking_in.max_buys,
min_price   = tracking_in.max_sells, amount_traded=tracking_in.trade_amounts, trade_value=tracking_in.trade_cashes,
direction   = tracking_in.trade_directions, lob_depth=tracking_in.LOB_depth_hit, stop_loss_order=tracking_in.stop_loss_order, agent_type=tracking_in.agent_type)



last_time           = last(first(data.time,total_sim_time))
times_plot          = unix2datetime.(first(data.time,total_sim_time) ./ 1000)
last_simulated_time = findnearest(df.time,last_time)[1]
sim_times_plot      = unix2datetime.(first(df.time,last_simulated_time) ./ 1000)
#last_stop_time=findnearest(df_stops.time,last_time)[1]
#stop_dates=unix2datetime.(first(df_stops.time,last_stop_time) ./ 1000)

print("\nPlotting!!!")
# Create traces
trace1 = PlotlyJS.scatter(x=times_plot , y=first(data.price,total_sim_time),
                    mode="lines",
                    name="Price")
trace2 = PlotlyJS.scatter(x=sim_times_plot, y=first(df.price,last_simulated_time),
                    mode="lines",
                    name="Simulated Price")

plot([trace1, trace2])

p = plot([trace1, trace2], Layout(title= string(plot_title) *" Seed: " *string(seed_num)))
display(p)
print("\nPlotted")



print("\nDoing accounts stuff...")

##################### GET ACCOUNT POSITIONS ######################
for i in range(1, length = length(accounts))
    #Get every agent's starting starting_balances
    starting_balances = starting_shares * price   +    starting_cash
    #Mark to market the value of the shares
    end_value = accounts[i][2]*price+accounts[i][3]
    #Get pnl of agent
    end_value - starting_balances
    append!(accounts[i], end_value)
    append!(accounts[i], end_value - starting_balances)
end

account_df = DataFrame(agent_id=getindex.(accounts,1), type=getindex.(getindex.(accounts, 4), 1) ,end_value=getindex.(accounts, 5), pnl=getindex.(accounts, 6))
gd = groupby(account_df, :type)
accounts_pnls = combine(gd, :pnl => sum)
print("\nThis is the position of the agent types: ", accounts_pnls, "\nAssume the 'market' profited: ", -1*sum(getindex.(accounts, 6)))

accounts_df = DataFrame(type=getindex.(getindex.(accounts, 4), 1), shares = getindex.(getindex.(accounts, 2), 1),cash = getindex.(getindex.(accounts, 3), 1),end_value=getindex.(accounts, 5), pnl=getindex.(accounts, 6))


if save_output_data==1
####### SECTION TO SAVE STUFF #####
mkpath(MAIN_SAVE_PATH) # Creates three directories: "my", "test", and "dir"
# try; mkdir(MAIN_SAVE_PATH); catch; print("Directory ALready Exists :) "); end
file_name = MAIN_SAVE_PATH * exp_name *"_" * string(seed_num)
# #Save the file
jdffile = JDF.save(file_name*"_Accounts.jdf", accounts_df)
jdffile = JDF.save(file_name*"_Data.jdf", df[:, [:time, :price, :amount_traded, :direction, :agent_type]])
print("\n\nSaved the relevant Data :) \n\n")
end  #End saving stuff



#############################################
# #Load files - Use these function to load in previously saved trials
# acocunts_df2 = DataFrame(JDF.load(file_name*"_Accounts.jdf"))
# df_2 = DataFrame(JDF.load(file_name*"_Data.jdf"))


print("\nFINISHED - this sim - ", seed_num)



end #End loop of num of sims we wanted to try 
