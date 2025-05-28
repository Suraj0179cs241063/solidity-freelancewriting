// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title FreelanceWriting
 * @dev A decentralized platform for freelance writing jobs
 * @author Freelance Writing Platform Team
 */
contract Project {
    
    // Job status enumeration
    enum JobStatus { Open, InProgress, Completed, Disputed, Cancelled }
    
    // Structure to represent a writing job
    struct WritingJob {
        uint256 jobId;
        address client;
        address writer;
        string title;
        string description;
        uint256 payment;
        uint256 deadline;
        JobStatus status;
        string deliverable; // IPFS hash or content link
        uint256 createdAt;
    }
    
    // State variables
    mapping(uint256 => WritingJob) public jobs;
    mapping(address => uint256[]) public clientJobs;
    mapping(address => uint256[]) public writerJobs;
    mapping(address => uint256) public writerRatings; // Simple rating system
    mapping(address => uint256) public totalRatings;
    
    uint256 public jobCounter;
    uint256 public platformFee = 25; // 2.5% platform fee (basis points)
    address public owner;
    
    // Events
    event JobCreated(uint256 indexed jobId, address indexed client, uint256 payment, uint256 deadline);
    event JobAccepted(uint256 indexed jobId, address indexed writer);
    event JobCompleted(uint256 indexed jobId, string deliverable);
    event PaymentReleased(uint256 indexed jobId, address indexed writer, uint256 amount);
    event JobCancelled(uint256 indexed jobId, address indexed client);
    event WriterRated(address indexed writer, uint256 rating);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyClient(uint256 _jobId) {
        require(msg.sender == jobs[_jobId].client, "Only client can call this function");
        _;
    }
    
    modifier onlyWriter(uint256 _jobId) {
        require(msg.sender == jobs[_jobId].writer, "Only assigned writer can call this function");
        _;
    }
    
    modifier jobExists(uint256 _jobId) {
        require(_jobId < jobCounter, "Job does not exist");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        jobCounter = 0;
    }
    
    /**
     * @dev Core Function 1: Create a new writing job
     * @param _title Title of the writing job
     * @param _description Detailed description of the writing requirements
     * @param _deadline Unix timestamp for job deadline
     */
    function createJob(
        string memory _title,
        string memory _description,
        uint256 _deadline
    ) external payable {
        require(msg.value > 0, "Payment must be greater than 0");
        require(_deadline > block.timestamp, "Deadline must be in the future");
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(bytes(_description).length > 0, "Description cannot be empty");
        
        WritingJob storage newJob = jobs[jobCounter];
        newJob.jobId = jobCounter;
        newJob.client = msg.sender;
        newJob.title = _title;
        newJob.description = _description;
        newJob.payment = msg.value;
        newJob.deadline = _deadline;
        newJob.status = JobStatus.Open;
        newJob.createdAt = block.timestamp;
        
        clientJobs[msg.sender].push(jobCounter);
        
        emit JobCreated(jobCounter, msg.sender, msg.value, _deadline);
        jobCounter++;
    }
    
    /**
     * @dev Core Function 2: Accept and complete a writing job
     * @param _jobId ID of the job to accept
     * @param _deliverable IPFS hash or link to the completed work
     */
    function acceptAndCompleteJob(
        uint256 _jobId,
        string memory _deliverable
    ) external jobExists(_jobId) {
        WritingJob storage job = jobs[_jobId];
        
        require(job.status == JobStatus.Open, "Job is not available");
        require(block.timestamp <= job.deadline, "Job deadline has passed");
        require(bytes(_deliverable).length > 0, "Deliverable cannot be empty");
        require(msg.sender != job.client, "Client cannot accept their own job");
        
        // Accept the job
        job.writer = msg.sender;
        job.status = JobStatus.InProgress;
        writerJobs[msg.sender].push(_jobId);
        
        emit JobAccepted(_jobId, msg.sender);
        
        // Complete the job immediately with deliverable
        job.deliverable = _deliverable;
        job.status = JobStatus.Completed;
        
        emit JobCompleted(_jobId, _deliverable);
        
        // Auto-release payment (in a real-world scenario, this might require client approval)
        _releasePayment(_jobId);
    }
    
    /**
     * @dev Core Function 3: Release payment and rate writer
     * @param _jobId ID of the completed job
     * @param _rating Rating for the writer (1-5 scale)
     */
    function releasePaymentAndRate(
        uint256 _jobId,
        uint256 _rating
    ) external onlyClient(_jobId) jobExists(_jobId) {
        require(_rating >= 1 && _rating <= 5, "Rating must be between 1 and 5");
        
        WritingJob storage job = jobs[_jobId];
        require(job.status == JobStatus.Completed, "Job is not completed yet");
        require(job.writer != address(0), "No writer assigned");
        
        // Release payment
        _releasePayment(_jobId);
        
        // Update writer rating
        writerRatings[job.writer] += _rating;
        totalRatings[job.writer]++;
        
        emit WriterRated(job.writer, _rating);
    }
    
    /**
     * @dev Internal function to release payment
     * @param _jobId ID of the job to release payment for
     */
    function _releasePayment(uint256 _jobId) internal {
        WritingJob storage job = jobs[_jobId];
        
        uint256 platformFeeAmount = (job.payment * platformFee) / 10000;
        uint256 writerPayment = job.payment - platformFeeAmount;
        
        // Transfer payment to writer
        payable(job.writer).transfer(writerPayment);
        
        // Transfer platform fee to owner
        payable(owner).transfer(platformFeeAmount);
        
        emit PaymentReleased(_jobId, job.writer, writerPayment);
    }
    
    /**
     * @dev Cancel a job (only if no writer assigned)
     * @param _jobId ID of the job to cancel
     */
    function cancelJob(uint256 _jobId) external onlyClient(_jobId) jobExists(_jobId) {
        WritingJob storage job = jobs[_jobId];
        require(job.status == JobStatus.Open, "Can only cancel open jobs");
        
        job.status = JobStatus.Cancelled;
        
        // Refund payment to client
        payable(job.client).transfer(job.payment);
        
        emit JobCancelled(_jobId, job.client);
    }
    
    /**
     * @dev Get writer's average rating
     * @param _writer Address of the writer
     * @return Average rating (multiplied by 100 for precision)
     */
    function getWriterRating(address _writer) external view returns (uint256) {
        if (totalRatings[_writer] == 0) return 0;
        return (writerRatings[_writer] * 100) / totalRatings[_writer];
    }
    
    /**
     * @dev Get job details
     * @param _jobId ID of the job
     * @return WritingJob struct
     */
    function getJob(uint256 _jobId) external view jobExists(_jobId) returns (WritingJob memory) {
        return jobs[_jobId];
    }
    
    /**
     * @dev Get jobs created by a client
     * @param _client Address of the client
     * @return Array of job IDs
     */
    function getClientJobs(address _client) external view returns (uint256[] memory) {
        return clientJobs[_client];
    }
    
    /**
     * @dev Get jobs accepted by a writer
     * @param _writer Address of the writer
     * @return Array of job IDs
     */
    function getWriterJobs(address _writer) external view returns (uint256[] memory) {
        return writerJobs[_writer];
    }
    
    /**
     * @dev Update platform fee (only owner)
     * @param _newFee New platform fee in basis points
     */
    function updatePlatformFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 1000, "Platform fee cannot exceed 10%");
        platformFee = _newFee;
    }
    
    /**
     * @dev Withdraw accumulated platform fees (only owner)
     */
    function withdrawPlatformFees() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    /**
     * @dev Get contract balance
     * @return Contract balance in wei
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
